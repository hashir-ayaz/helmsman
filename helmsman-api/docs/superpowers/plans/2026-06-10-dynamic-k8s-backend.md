# Dynamic Kubernetes Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four hardcoded read-only resource handlers with a generic, dynamic-client backend that serves list/get/yaml/apply/delete/patch for any Kubernetes resource (built-ins + CRDs), plus typed `scale`/`restart` actions and SSE log streaming, across multiple kubeconfig contexts.

**Architecture:** A `cluster.Provider` caches a per-context client bundle (typed + dynamic + discovery + RESTMapper). A `k8s` operations layer resolves a URL resource string to a GVR and performs CRUD over the dynamic client, fetching lists in the API server's Server-Side Table format. Thin HTTP handlers (`ResourceHandler`, `ActionHandler`, `LogHandler`, `ContextHandler`) wrap those operations behind the existing `APIResponse` envelope. The backend stays stateless (context is a URL path segment) to support the client's polling model.

**Tech Stack:** Go 1.26, `k8s.io/client-go` v0.32.3 (`dynamic`, `discovery`, `restmapper`, `kubernetes`), stdlib `net/http` 1.22 routing, `sigs.k8s.io/yaml`.

---

## File Structure

**New files**
- `internal/cluster/provider.go` — `Provider`, `ClientBundle`, `ContextInfo`, kubeconfig-backed implementation + bundle cache.
- `internal/k8s/resolver.go` — resource-string → GVR + namespaced-ness via RESTMapper.
- `internal/k8s/resources.go` — generic list (Table) / get / yaml / delete / patch / apply over a `ClientBundle`.
- `internal/k8s/actions.go` — `Scale`, `Restart`.
- `internal/k8s/logs.go` — pod log stream opener.
- `internal/handler/table.go` — `TablePayload` + pure `tableToPayload`.
- `internal/handler/errors.go` — `statusFromK8sErr` mapping.
- `internal/handler/resources.go` — `ResourceHandler`.
- `internal/handler/actions.go` — `ActionHandler`.
- `internal/handler/logs.go` — `LogHandler` (SSE).
- `internal/handler/contexts.go` — `ContextHandler`.
- `internal/handler/handlers.go` — `Handlers` set + `bundleFor` helper + `recoverer` middleware.

**Modified**
- `internal/handler/response.go` — add `writeStatus`.
- `internal/server/server.go` — new route table + `New(port, Handlers)` signature.
- `cmd/server/main.go` — wire `cluster.Provider` + `Handlers`.

**Deleted (migration, Task 11)**
- `internal/handler/{pods,deployments,services,namespaces}.go`
- `internal/k8s/{pods,deployments,services,namespaces}.go`
- `internal/k8s/client.go` (superseded by `cluster.Provider`)
- `internal/k8s/helpers.go` (if `formatAge` ends up unused)

---

## Task 1: cluster.Provider — contexts + cached bundles

**Files:**
- Create: `internal/cluster/provider.go`
- Test: `internal/cluster/provider_test.go`

- [ ] **Step 1: Write the failing test**

```go
package cluster

import (
	"os"
	"path/filepath"
	"testing"
)

const twoContextKubeconfig = `
apiVersion: v1
kind: Config
current-context: dev
clusters:
- name: dev-cluster
  cluster: {server: https://dev.example:6443}
- name: prod-cluster
  cluster: {server: https://prod.example:6443}
contexts:
- name: dev
  context: {cluster: dev-cluster, namespace: dev-ns}
- name: prod
  context: {cluster: prod-cluster}
users: []
`

func writeKubeconfig(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	if err := os.WriteFile(path, []byte(twoContextKubeconfig), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestProviderContexts(t *testing.T) {
	p, err := NewProvider(writeKubeconfig(t))
	if err != nil {
		t.Fatalf("NewProvider: %v", err)
	}
	if got := p.Current(); got != "dev" {
		t.Errorf("Current() = %q, want dev", got)
	}
	ctxs := p.Contexts()
	if len(ctxs) != 2 {
		t.Fatalf("got %d contexts, want 2", len(ctxs))
	}
	byName := map[string]ContextInfo{}
	for _, c := range ctxs {
		byName[c.Name] = c
	}
	if !byName["dev"].IsCurrent {
		t.Error("dev should be current")
	}
	if byName["dev"].Namespace != "dev-ns" {
		t.Errorf("dev namespace = %q, want dev-ns", byName["dev"].Namespace)
	}
	if byName["dev"].Cluster != "dev-cluster" {
		t.Errorf("dev cluster = %q, want dev-cluster", byName["dev"].Cluster)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/cluster/ -run TestProviderContexts -v`
Expected: FAIL — `undefined: NewProvider` / `ContextInfo`.

- [ ] **Step 3: Write the implementation**

```go
// Package cluster manages Kubernetes client connections, one bundle per
// kubeconfig context, built lazily and cached.
package cluster

import (
	"fmt"
	"sync"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/client-go/discovery"
	memory "k8s.io/client-go/discovery/cached/memory"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
)

// ClientBundle holds every client a handler needs for one cluster context.
type ClientBundle struct {
	Typed     kubernetes.Interface
	Dynamic   dynamic.Interface
	Discovery discovery.DiscoveryInterface
	Mapper    meta.RESTMapper
}

// ContextInfo describes a selectable kubeconfig context for the UI.
type ContextInfo struct {
	Name      string `json:"name"`
	Cluster   string `json:"cluster"`
	Namespace string `json:"namespace"`
	IsCurrent bool   `json:"isCurrent"`
}

// Provider enumerates contexts and supplies cached client bundles.
type Provider interface {
	Contexts() []ContextInfo
	Current() string
	Bundle(contextName string) (*ClientBundle, error)
}

type kubeProvider struct {
	raw     clientcmd.ClientConfig
	current string
	infos   []ContextInfo
	loader  clientcmd.ClientConfigLoadingRules

	mu    sync.RWMutex
	cache map[string]*ClientBundle
}

// NewProvider loads the kubeconfig at path (honouring $KUBECONFIG merge rules
// when path is empty) and prepares lazy per-context bundles.
func NewProvider(kubeconfigPath string) (Provider, error) {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	if kubeconfigPath != "" {
		rules.ExplicitPath = kubeconfigPath
	}
	cfg, err := rules.Load()
	if err != nil {
		return nil, fmt.Errorf("load kubeconfig: %w", err)
	}

	infos := make([]ContextInfo, 0, len(cfg.Contexts))
	for name, c := range cfg.Contexts {
		infos = append(infos, ContextInfo{
			Name:      name,
			Cluster:   c.Cluster,
			Namespace: c.Namespace,
			IsCurrent: name == cfg.CurrentContext,
		})
	}

	return &kubeProvider{
		raw:     clientcmd.NewDefaultClientConfig(*cfg, &clientcmd.ConfigOverrides{}),
		current: cfg.CurrentContext,
		infos:   infos,
		loader:  *rules,
		cache:   map[string]*ClientBundle{},
	}, nil
}

func (p *kubeProvider) Contexts() []ContextInfo { return p.infos }
func (p *kubeProvider) Current() string         { return p.current }

func (p *kubeProvider) Bundle(contextName string) (*ClientBundle, error) {
	if contextName == "" {
		contextName = p.current
	}
	p.mu.RLock()
	if b, ok := p.cache[contextName]; ok {
		p.mu.RUnlock()
		return b, nil
	}
	p.mu.RUnlock()

	b, err := p.build(contextName)
	if err != nil {
		return nil, err
	}
	p.mu.Lock()
	p.cache[contextName] = b
	p.mu.Unlock()
	return b, nil
}

func (p *kubeProvider) build(contextName string) (*ClientBundle, error) {
	restCfg, err := p.restConfig(contextName)
	if err != nil {
		return nil, err
	}
	typed, err := kubernetes.NewForConfig(restCfg)
	if err != nil {
		return nil, fmt.Errorf("typed client for %q: %w", contextName, err)
	}
	dyn, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return nil, fmt.Errorf("dynamic client for %q: %w", contextName, err)
	}
	disco := memory.NewMemCacheClient(typed.Discovery())
	mapper := restmapper.NewDeferredDiscoveryRESTMapper(disco)
	return &ClientBundle{Typed: typed, Dynamic: dyn, Discovery: disco, Mapper: mapper}, nil
}

func (p *kubeProvider) restConfig(contextName string) (*rest.Config, error) {
	// In-cluster sentinel keeps parity with the old single-cluster mode.
	if contextName == "in-cluster" {
		return rest.InClusterConfig()
	}
	overrides := &clientcmd.ConfigOverrides{CurrentContext: contextName}
	cc := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(&p.loader, overrides)
	restCfg, err := cc.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("rest config for %q: %w", contextName, err)
	}
	return restCfg, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/cluster/ -run TestProviderContexts -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/cluster/provider.go internal/cluster/provider_test.go
git commit -m "feat(cluster): kubeconfig-backed Provider with cached per-context bundles"
```

---

## Task 2: k8s.Resolve — resource string → GVR

**Files:**
- Create: `internal/k8s/resolver.go`
- Test: `internal/k8s/resolver_test.go`

- [ ] **Step 1: Write the failing test**

```go
package k8s

import (
	"testing"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/client-go/kubernetes/scheme"
)

func TestResolve(t *testing.T) {
	mapper := testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme)

	tests := []struct {
		param      string
		wantRes    string
		wantGroup  string
		namespaced bool
	}{
		{"pods", "pods", "", true},
		{"deployments", "deployments", "apps", true},
		{"deployments.apps", "deployments", "apps", true},
		{"namespaces", "namespaces", "", false},
		{"nodes", "nodes", "", false},
	}
	for _, tt := range tests {
		ref, err := Resolve(mapper, tt.param)
		if err != nil {
			t.Fatalf("Resolve(%q): %v", tt.param, err)
		}
		if ref.GVR.Resource != tt.wantRes || ref.GVR.Group != tt.wantGroup {
			t.Errorf("Resolve(%q) = %s/%s, want %s/%s", tt.param, ref.GVR.Group, ref.GVR.Resource, tt.wantGroup, tt.wantRes)
		}
		if ref.Namespaced != tt.namespaced {
			t.Errorf("Resolve(%q).Namespaced = %v, want %v", tt.param, ref.Namespaced, tt.namespaced)
		}
	}

	if _, err := Resolve(mapper, "widgets"); err == nil {
		t.Error("expected error for unknown resource")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/k8s/ -run TestResolve -v`
Expected: FAIL — `undefined: Resolve`.

- [ ] **Step 3: Write the implementation**

```go
package k8s

import (
	"fmt"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

// ResourceRef is a resolved resource: its GVR and whether it is namespaced.
type ResourceRef struct {
	GVR        schema.GroupVersionResource
	Namespaced bool
}

// Resolve turns a URL resource identifier ("pods", "deployments",
// "deployments.apps", "virtualservices.networking.istio.io") into a concrete
// GVR using the cluster's RESTMapper.
func Resolve(mapper meta.RESTMapper, resourceParam string) (ResourceRef, error) {
	gr := schema.ParseGroupResource(resourceParam)
	gvr, err := mapper.ResourceFor(schema.GroupVersionResource{Group: gr.Group, Resource: gr.Resource})
	if err != nil {
		return ResourceRef{}, fmt.Errorf("unknown resource %q: %w", resourceParam, err)
	}
	gvk, err := mapper.KindFor(gvr)
	if err != nil {
		return ResourceRef{}, fmt.Errorf("kind for %q: %w", resourceParam, err)
	}
	mapping, err := mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		return ResourceRef{}, fmt.Errorf("mapping for %q: %w", resourceParam, err)
	}
	return ResourceRef{
		GVR:        gvr,
		Namespaced: mapping.Scope.Name() == meta.RESTScopeNameNamespace,
	}, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/k8s/ -run TestResolve -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/k8s/resolver.go internal/k8s/resolver_test.go
git commit -m "feat(k8s): GVR resolver from URL resource strings"
```

---

## Task 3: Table payload reshaping

**Files:**
- Create: `internal/handler/table.go`
- Test: `internal/handler/table_test.go`

- [ ] **Step 1: Write the failing test**

```go
package handler

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

func TestTableToPayload(t *testing.T) {
	table := &metav1.Table{
		ColumnDefinitions: []metav1.TableColumnDefinition{
			{Name: "Name", Type: "string", Priority: 0},
			{Name: "Status", Type: "string", Priority: 0},
		},
		Rows: []metav1.TableRow{
			{
				Cells:  []any{"nginx-abc", "Running"},
				Object: runtime.RawExtension{Raw: []byte(`{"metadata":{"name":"nginx-abc","namespace":"default","uid":"u-1"}}`)},
			},
		},
	}

	got := tableToPayload(table)

	if len(got.Columns) != 2 || got.Columns[0].Name != "Name" {
		t.Fatalf("columns = %+v", got.Columns)
	}
	if len(got.Rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(got.Rows))
	}
	row := got.Rows[0]
	if row.Cells[0] != "nginx-abc" || row.Cells[1] != "Running" {
		t.Errorf("cells = %+v", row.Cells)
	}
	if row.Object.Name != "nginx-abc" || row.Object.Namespace != "default" || row.Object.UID != "u-1" {
		t.Errorf("object stub = %+v", row.Object)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/handler/ -run TestTableToPayload -v`
Expected: FAIL — `undefined: tableToPayload`.

- [ ] **Step 3: Write the implementation**

```go
package handler

import (
	"encoding/json"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// TableColumn mirrors a server-side printer column.
type TableColumn struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	Priority int32  `json:"priority"`
}

// RowObject is the minimal object identity the client needs to build follow-up URLs.
type RowObject struct {
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	UID       string `json:"uid"`
}

// TableRow is one printed row plus its object identity.
type TableRow struct {
	Cells  []any     `json:"cells"`
	Object RowObject `json:"object"`
}

// TablePayload is the list response shape (Data field of APIResponse).
type TablePayload struct {
	Columns []TableColumn `json:"columns"`
	Rows    []TableRow    `json:"rows"`
}

// tableToPayload reshapes a server-side metav1.Table into the API payload.
func tableToPayload(t *metav1.Table) TablePayload {
	cols := make([]TableColumn, 0, len(t.ColumnDefinitions))
	for _, c := range t.ColumnDefinitions {
		cols = append(cols, TableColumn{Name: c.Name, Type: c.Type, Priority: c.Priority})
	}

	rows := make([]TableRow, 0, len(t.Rows))
	for _, r := range t.Rows {
		var meta struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
				UID       string `json:"uid"`
			} `json:"metadata"`
		}
		if len(r.Object.Raw) > 0 {
			_ = json.Unmarshal(r.Object.Raw, &meta)
		}
		rows = append(rows, TableRow{
			Cells: r.Cells,
			Object: RowObject{
				Namespace: meta.Metadata.Namespace,
				Name:      meta.Metadata.Name,
				UID:       meta.Metadata.UID,
			},
		})
	}
	return TablePayload{Columns: cols, Rows: rows}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/handler/ -run TestTableToPayload -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/handler/table.go internal/handler/table_test.go
git commit -m "feat(handler): server-side Table to API payload reshaping"
```

---

## Task 4: K8s error → HTTP status mapping

**Files:**
- Create: `internal/handler/errors.go`
- Test: `internal/handler/errors_test.go`

- [ ] **Step 1: Write the failing test**

```go
package handler

import (
	"net/http"
	"testing"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

func TestStatusFromK8sErr(t *testing.T) {
	gr := schema.GroupResource{Resource: "pods"}
	cases := []struct {
		err  error
		want int
	}{
		{apierrors.NewNotFound(gr, "x"), http.StatusNotFound},
		{apierrors.NewForbidden(gr, "x", nil), http.StatusForbidden},
		{apierrors.NewConflict(gr, "x", nil), http.StatusConflict},
		{apierrors.NewInvalid(schema.GroupKind{Kind: "Pod"}, "x", nil), http.StatusUnprocessableEntity},
		{&metav1.Status{}, http.StatusInternalServerError},
	}
	for _, c := range cases {
		if got, _ := statusFromK8sErr(c.err); got != c.want {
			t.Errorf("status for %v = %d, want %d", c.err, got, c.want)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/handler/ -run TestStatusFromK8sErr -v`
Expected: FAIL — `undefined: statusFromK8sErr`.

- [ ] **Step 3: Write the implementation**

```go
package handler

import (
	"net/http"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
)

// statusFromK8sErr maps a Kubernetes API error to an HTTP status and a
// client-safe message. Forbidden is surfaced verbatim so the UI can show
// RBAC problems; everything else gets a sanitized message.
func statusFromK8sErr(err error) (int, string) {
	switch {
	case apierrors.IsNotFound(err):
		return http.StatusNotFound, "resource not found"
	case apierrors.IsForbidden(err):
		return http.StatusForbidden, err.Error()
	case apierrors.IsConflict(err):
		return http.StatusConflict, "resource conflict, retry"
	case apierrors.IsInvalid(err), apierrors.IsBadRequest(err):
		return http.StatusUnprocessableEntity, err.Error()
	case apierrors.IsUnauthorized(err):
		return http.StatusUnauthorized, "unauthorized"
	case meta.IsNoMatchError(err):
		return http.StatusNotFound, err.Error()
	default:
		return http.StatusInternalServerError, "internal error"
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/handler/ -run TestStatusFromK8sErr -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/handler/errors.go internal/handler/errors_test.go
git commit -m "feat(handler): map Kubernetes API errors to HTTP status"
```

---

## Task 5: k8s resource operations (get / yaml / delete / patch / apply-parse / table fetch)

**Files:**
- Create: `internal/k8s/resources.go`
- Test: `internal/k8s/resources_test.go`

- [ ] **Step 1: Write the failing test** (covers dynamic Get/Delete + YAML parse; List/Apply are exercised live in Task 12)

```go
package k8s

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	dynamicfake "k8s.io/client-go/dynamic/fake"
)

var cmGVR = schema.GroupVersionResource{Version: "v1", Resource: "configmaps"}

func newCM(name string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "ConfigMap",
		"metadata": map[string]any{"name": name, "namespace": "default"},
	}}
}

func fakeDyn(objs ...runtime.Object) *dynamicfake.FakeDynamicClient {
	return dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), objs...)
}

func TestGetAndDelete(t *testing.T) {
	dyn := fakeDyn(newCM("cm-1"))
	ref := ResourceRef{GVR: cmGVR, Namespaced: true}
	ctx := context.Background()

	obj, err := Get(ctx, dyn, ref, "default", "cm-1")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if obj.GetName() != "cm-1" {
		t.Errorf("name = %q", obj.GetName())
	}

	if err := Delete(ctx, dyn, ref, "default", "cm-1"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := dyn.Resource(cmGVR).Namespace("default").Get(ctx, "cm-1", metav1.GetOptions{}); err == nil {
		t.Error("expected cm-1 to be gone")
	}
}

func TestParseApply(t *testing.T) {
	yaml := []byte("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: parsed\n  namespace: default\n")
	obj, gvk, err := ParseManifest(yaml)
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}
	if gvk.Kind != "ConfigMap" {
		t.Errorf("kind = %q", gvk.Kind)
	}
	if obj.GetName() != "parsed" {
		t.Errorf("name = %q", obj.GetName())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/k8s/ -run 'TestGetAndDelete|TestParseApply' -v`
Expected: FAIL — `undefined: Get` / `Delete` / `ParseManifest`.

- [ ] **Step 3: Write the implementation**

```go
package k8s

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/hashirayaz/k67s-api/internal/cluster"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"sigs.k8s.io/yaml"
)

const fieldManager = "k67s"

// ListOptions are the pass-through list filters from query params.
type ListOptions struct {
	LabelSelector string
	FieldSelector string
}

func dynResource(dyn dynamic.Interface, ref ResourceRef, namespace string) dynamic.ResourceInterface {
	r := dyn.Resource(ref.GVR)
	if ref.Namespaced {
		return r.Namespace(namespace)
	}
	return r
}

// FetchTable lists resources in the server-side Table format. It issues a raw
// REST GET with the Table Accept header and JSON-decodes the result, avoiding
// per-type serializer wiring.
func FetchTable(ctx context.Context, b *cluster.ClientBundle, ref ResourceRef, namespace string, opts ListOptions) (*metav1.Table, error) {
	req := b.Discovery.RESTClient().Get().
		AbsPath(absPath(ref, namespace)).
		SetHeader("Accept", "application/json;as=Table;v=v1;g=meta.k8s.io, application/json")
	if opts.LabelSelector != "" {
		req = req.Param("labelSelector", opts.LabelSelector)
	}
	if opts.FieldSelector != "" {
		req = req.Param("fieldSelector", opts.FieldSelector)
	}
	raw, err := req.Do(ctx).Raw()
	if err != nil {
		return nil, fmt.Errorf("list %s: %w", ref.GVR.Resource, err)
	}
	var table metav1.Table
	if err := json.Unmarshal(raw, &table); err != nil {
		return nil, fmt.Errorf("decode table for %s: %w", ref.GVR.Resource, err)
	}
	return &table, nil
}

func absPath(ref ResourceRef, namespace string) string {
	gv := ref.GVR.GroupVersion()
	var prefix string
	if gv.Group == "" {
		prefix = "/api/" + gv.Version
	} else {
		prefix = "/apis/" + gv.Group + "/" + gv.Version
	}
	if ref.Namespaced && namespace != "" {
		return prefix + "/namespaces/" + namespace + "/" + ref.GVR.Resource
	}
	return prefix + "/" + ref.GVR.Resource
}

// Get returns a single object.
func Get(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) (*unstructured.Unstructured, error) {
	obj, err := dynResource(dyn, ref, namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("get %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return obj, nil
}

// YAML returns a single object serialized as YAML.
func YAML(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) ([]byte, error) {
	obj, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return nil, err
	}
	out, err := yaml.Marshal(obj.Object)
	if err != nil {
		return nil, fmt.Errorf("marshal yaml: %w", err)
	}
	return out, nil
}

// Delete removes an object.
func Delete(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) error {
	if err := dynResource(dyn, ref, namespace).Delete(ctx, name, metav1.DeleteOptions{}); err != nil {
		return fmt.Errorf("delete %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}

// Patch applies a merge or JSON patch to an object.
func Patch(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, pt types.PatchType, data []byte) (*unstructured.Unstructured, error) {
	obj, err := dynResource(dyn, ref, namespace).Patch(ctx, name, pt, data, metav1.PatchOptions{})
	if err != nil {
		return nil, fmt.Errorf("patch %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return obj, nil
}

// ParseManifest decodes a YAML/JSON manifest into an unstructured object and
// returns its embedded GVK.
func ParseManifest(manifest []byte) (*unstructured.Unstructured, schema.GroupVersionKind, error) {
	jsonBytes, err := yaml.YAMLToJSON(manifest)
	if err != nil {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("yaml to json: %w", err)
	}
	obj := &unstructured.Unstructured{}
	if err := obj.UnmarshalJSON(jsonBytes); err != nil {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("decode manifest: %w", err)
	}
	gvk := obj.GroupVersionKind()
	if gvk.Empty() {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("manifest missing apiVersion/kind")
	}
	return obj, gvk, nil
}

// Apply performs a server-side apply of a manifest. ref must already be
// resolved from the manifest's GVK by the caller.
func Apply(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, obj *unstructured.Unstructured) (*unstructured.Unstructured, error) {
	data, err := obj.MarshalJSON()
	if err != nil {
		return nil, fmt.Errorf("marshal apply: %w", err)
	}
	res, err := dynResource(dyn, ref, obj.GetNamespace()).Patch(
		ctx, obj.GetName(), types.ApplyPatchType, data,
		metav1.PatchOptions{FieldManager: fieldManager, Force: ptrBool(true)},
	)
	if err != nil {
		return nil, fmt.Errorf("apply %s/%s: %w", ref.GVR.Resource, obj.GetName(), err)
	}
	return res, nil
}

func ptrBool(b bool) *bool { return &b }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/k8s/ -run 'TestGetAndDelete|TestParseApply' -race -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/k8s/resources.go internal/k8s/resources_test.go
git commit -m "feat(k8s): generic dynamic CRUD + server-side Table list + apply parsing"
```

---

## Task 6: k8s actions (scale, restart)

**Files:**
- Create: `internal/k8s/actions.go`
- Test: `internal/k8s/actions_test.go`

- [ ] **Step 1: Write the failing test**

```go
package k8s

import (
	"context"
	"testing"

	"k8s.io/apimachinery/pkg/runtime/schema"
)

var deployGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}

func TestRestartPatchShape(t *testing.T) {
	// Restart must produce a strategic-merge patch with the restartedAt annotation.
	patch := restartPatch("2026-06-10T00:00:00Z")
	want := `{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"2026-06-10T00:00:00Z"}}}}}`
	if string(patch) != want {
		t.Errorf("restartPatch = %s, want %s", patch, want)
	}
}

func TestScalePatchShape(t *testing.T) {
	if got := string(scalePatch(3)); got != `{"spec":{"replicas":3}}` {
		t.Errorf("scalePatch = %s", got)
	}
}

func TestScaleCallsSubresource(t *testing.T) {
	dyn := fakeDyn()
	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	// Just assert it does not panic / returns a clean error path on missing object.
	if err := Scale(context.Background(), dyn, ref, "default", "missing", 3); err == nil {
		t.Error("expected error scaling missing deployment")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/k8s/ -run 'Restart|Scale' -v`
Expected: FAIL — `undefined: restartPatch` / `scalePatch` / `Scale`.

- [ ] **Step 3: Write the implementation**

```go
package k8s

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
)

func scalePatch(replicas int32) []byte {
	return []byte(fmt.Sprintf(`{"spec":{"replicas":%d}}`, replicas))
}

func restartPatch(restartedAt string) []byte {
	return []byte(fmt.Sprintf(
		`{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":%q}}}}}`,
		restartedAt,
	))
}

// Scale sets the replica count via the resource's scale subresource (works for
// deployments, statefulsets, replicasets).
func Scale(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, replicas int32) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType, scalePatch(replicas), metav1.PatchOptions{}, "scale",
	)
	if err != nil {
		return fmt.Errorf("scale %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}

// Restart triggers a rolling restart by stamping the pod-template restartedAt
// annotation (the same mechanism as `kubectl rollout restart`). restartedAt is
// supplied by the caller to keep the operation deterministic.
func Restart(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name, restartedAt string) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.StrategicMergePatchType, restartPatch(restartedAt), metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("restart %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/k8s/ -run 'Restart|Scale' -race -v`
Expected: PASS (the scale-missing test asserts the error path).

- [ ] **Step 5: Commit**

```bash
git add internal/k8s/actions.go internal/k8s/actions_test.go
git commit -m "feat(k8s): scale and rollout-restart actions"
```

---

## Task 7: k8s pod log streaming

**Files:**
- Create: `internal/k8s/logs.go`

- [ ] **Step 1: Write the implementation** (thin wrapper around typed client; behaviour verified live in Task 12)

```go
package k8s

import (
	"context"
	"io"

	"github.com/hashirayaz/k67s-api/internal/cluster"

	corev1 "k8s.io/api/core/v1"
)

// LogOptions are the pod log stream parameters.
type LogOptions struct {
	Container string
	Follow    bool
	Previous  bool
	TailLines *int64
}

// OpenLogStream returns a reader over a pod's logs. The caller must Close it.
func OpenLogStream(ctx context.Context, b *cluster.ClientBundle, namespace, pod string, opts LogOptions) (io.ReadCloser, error) {
	req := b.Typed.CoreV1().Pods(namespace).GetLogs(pod, &corev1.PodLogOptions{
		Container: opts.Container,
		Follow:    opts.Follow,
		Previous:  opts.Previous,
		TailLines: opts.TailLines,
	})
	return req.Stream(ctx)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `go build ./internal/k8s/`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add internal/k8s/logs.go
git commit -m "feat(k8s): pod log stream opener"
```

---

## Task 8: HTTP handlers (resources, actions, logs, contexts) + helpers

**Files:**
- Create: `internal/handler/handlers.go`, `internal/handler/resources.go`, `internal/handler/actions.go`, `internal/handler/logs.go`, `internal/handler/contexts.go`
- Modify: `internal/handler/response.go`
- Test: `internal/handler/handlers_test.go`

- [ ] **Step 1: Write the failing test** (contexts list + resource get via a fake provider)

```go
package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/k8s"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/dynamic"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/kubernetes/scheme"
)

type fakeProvider struct {
	bundle *cluster.ClientBundle
}

func (f *fakeProvider) Contexts() []cluster.ContextInfo {
	return []cluster.ContextInfo{{Name: "dev", Cluster: "c", Namespace: "default", IsCurrent: true}}
}
func (f *fakeProvider) Current() string { return "dev" }
func (f *fakeProvider) Bundle(string) (*cluster.ClientBundle, error) { return f.bundle, nil }

func newFakeProvider(objs ...runtime.Object) *fakeProvider {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), objs...)
	return &fakeProvider{bundle: &cluster.ClientBundle{
		Dynamic: dyn,
		Mapper:  testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme),
	}}
}

var _ dynamic.Interface = (*dynamicfake.FakeDynamicClient)(nil)

func TestContextsEndpoint(t *testing.T) {
	h := New(newFakeProvider())
	req := httptest.NewRequest(http.MethodGet, "/api/v1/contexts", nil)
	rec := httptest.NewRecorder()
	h.Contexts.List(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d", rec.Code)
	}
	var resp APIResponse
	json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Data == nil {
		t.Error("expected contexts in data")
	}
}

func TestResourceGet(t *testing.T) {
	cm := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "ConfigMap",
		"metadata": map[string]any{"name": "cm-1", "namespace": "default"},
	}}
	h := New(newFakeProvider(cm))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("resource", "configmaps")
	req.SetPathValue("name", "cm-1")
	rec := httptest.NewRecorder()
	h.Resources.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	_ = context.Background()
	_ = k8s.ResourceRef{}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/handler/ -run 'TestContextsEndpoint|TestResourceGet' -v`
Expected: FAIL — `undefined: New` and handler types.

- [ ] **Step 3a: Add `writeStatus` to `internal/handler/response.go`**

Append to the existing file (keep `writeSuccess`/`writeError` unchanged):

```go
// writeStatus writes a success payload with a non-200 status (e.g. 201 Created).
func writeStatus(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{Data: data})
}
```

- [ ] **Step 3b: Create `internal/handler/handlers.go`**

```go
package handler

import (
	"net/http"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/k8s"
)

// currentSentinel lets clients say "use the active context" without resolving it.
const currentSentinel = "_current"

// Handlers is the full handler set shared by the server.
type Handlers struct {
	Resources *ResourceHandler
	Actions   *ActionHandler
	Logs      *LogHandler
	Contexts  *ContextHandler
}

// New builds the handler set from a cluster provider.
func New(p cluster.Provider) Handlers {
	return Handlers{
		Resources: &ResourceHandler{provider: p},
		Actions:   &ActionHandler{provider: p},
		Logs:      &LogHandler{provider: p},
		Contexts:  &ContextHandler{provider: p},
	}
}

// bundleAndRef resolves the context bundle and the resource ref from the request.
func bundleAndRef(p cluster.Provider, r *http.Request) (*cluster.ClientBundle, k8s.ResourceRef, error) {
	b, err := bundleFor(p, r)
	if err != nil {
		return nil, k8s.ResourceRef{}, err
	}
	ref, err := k8s.Resolve(b.Mapper, r.PathValue("resource"))
	if err != nil {
		return nil, k8s.ResourceRef{}, err
	}
	return b, ref, nil
}

func bundleFor(p cluster.Provider, r *http.Request) (*cluster.ClientBundle, error) {
	ctxName := r.PathValue("ctx")
	if ctxName == currentSentinel {
		ctxName = ""
	}
	return p.Bundle(ctxName)
}

// recoverer converts panics into 500s so one bad request can't crash the server.
func recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				writeError(w, http.StatusInternalServerError, "internal error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
```

- [ ] **Step 3c: Create `internal/handler/contexts.go`**

```go
package handler

import (
	"net/http"

	"github.com/hashirayaz/k67s-api/internal/cluster"
)

type ContextHandler struct{ provider cluster.Provider }

// List godoc
//
//	@Summary	List kubeconfig contexts
//	@Tags		contexts
//	@Produce	json
//	@Success	200	{object}	APIResponse{data=[]cluster.ContextInfo}
//	@Router		/api/v1/contexts [get]
func (h *ContextHandler) List(w http.ResponseWriter, _ *http.Request) {
	writeSuccess(w, h.provider.Contexts())
}
```

- [ ] **Step 3d: Create `internal/handler/resources.go`**

```go
package handler

import (
	"io"
	"net/http"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/k8s"

	"k8s.io/apimachinery/pkg/types"
)

type ResourceHandler struct{ provider cluster.Provider }

func (h *ResourceHandler) fail(w http.ResponseWriter, err error) {
	code, msg := statusFromK8sErr(err)
	writeError(w, code, msg)
}

// List godoc
//
//	@Summary	List resources (server-side table)
//	@Tags		resources
//	@Produce	json
//	@Param		ctx			path		string	true	"Context name or _current"
//	@Param		resource	path		string	true	"Resource (e.g. pods, deployments.apps)"
//	@Success	200			{object}	APIResponse{data=TablePayload}
//	@Router		/api/v1/contexts/{ctx}/resources/{resource} [get]
func (h *ResourceHandler) List(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	opts := k8s.ListOptions{
		LabelSelector: r.URL.Query().Get("labelSelector"),
		FieldSelector: r.URL.Query().Get("fieldSelector"),
	}
	table, err := k8s.FetchTable(r.Context(), b, ref, r.PathValue("ns"), opts)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, tableToPayload(table))
}

// Get godoc
//
//	@Summary	Get one resource
//	@Tags		resources
//	@Produce	json
//	@Success	200	{object}	APIResponse
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [get]
func (h *ResourceHandler) Get(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	obj, err := k8s.Get(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, obj.Object)
}

// YAML godoc
//
//	@Summary	Get one resource as YAML
//	@Tags		resources
//	@Produce	plain
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml [get]
func (h *ResourceHandler) YAML(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	out, err := k8s.YAML(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"))
	if err != nil {
		h.fail(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/yaml")
	w.WriteHeader(http.StatusOK)
	w.Write(out)
}

// Delete godoc
//
//	@Summary	Delete one resource
//	@Tags		resources
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [delete]
func (h *ResourceHandler) Delete(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.Delete(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name")); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"deleted": r.PathValue("name")})
}

// Patch godoc
//
//	@Summary	Patch one resource (merge patch)
//	@Tags		resources
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [patch]
func (h *ResourceHandler) Patch(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read body")
		return
	}
	obj, err := k8s.Patch(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), types.MergePatchType, body)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, obj.Object)
}

// Apply godoc
//
//	@Summary	Apply a YAML manifest (server-side apply)
//	@Tags		resources
//	@Accept		plain
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/resources [post]
func (h *ResourceHandler) Apply(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read body")
		return
	}
	obj, gvk, err := k8s.ParseManifest(body)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	mapping, err := b.Mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		h.fail(w, err)
		return
	}
	ref := k8s.ResourceRef{GVR: mapping.Resource, Namespaced: mapping.Scope.Name() == "namespace"}
	res, err := k8s.Apply(r.Context(), b.Dynamic, ref, obj)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeStatus(w, http.StatusOK, res.Object)
}
```

- [ ] **Step 3e: Create `internal/handler/actions.go`**

```go
package handler

import (
	"encoding/json"
	"net/http"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/k8s"
)

type ActionHandler struct{ provider cluster.Provider }

func (h *ActionHandler) fail(w http.ResponseWriter, err error) {
	code, msg := statusFromK8sErr(err)
	writeError(w, code, msg)
}

type scaleRequest struct {
	Replicas int32 `json:"replicas"`
}

// Scale godoc
//
//	@Summary	Scale a workload
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale [post]
func (h *ActionHandler) Scale(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body scaleRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid scale request")
		return
	}
	ref, err := k8s.Resolve(b.Mapper, "deployments")
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.Scale(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), body.Replicas); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]any{"name": r.PathValue("name"), "replicas": body.Replicas})
}

type restartRequest struct {
	RestartedAt string `json:"restartedAt"`
}

// Restart godoc
//
//	@Summary	Rollout restart a workload
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart [post]
func (h *ActionHandler) Restart(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body restartRequest
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.RestartedAt == "" {
		writeError(w, http.StatusBadRequest, "restartedAt is required")
		return
	}
	ref, err := k8s.Resolve(b.Mapper, r.PathValue("workload"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.Restart(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), body.RestartedAt); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"restarted": r.PathValue("name")})
}
```

- [ ] **Step 3f: Create `internal/handler/logs.go`**

```go
package handler

import (
	"bufio"
	"net/http"
	"strconv"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/k8s"
)

type LogHandler struct{ provider cluster.Provider }

// Stream godoc
//
//	@Summary	Stream pod logs (SSE)
//	@Tags		logs
//	@Produce	text/event-stream
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log [get]
func (h *LogHandler) Stream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}

	opts := k8s.LogOptions{
		Container: r.URL.Query().Get("container"),
		Follow:    r.URL.Query().Get("follow") == "true",
		Previous:  r.URL.Query().Get("previous") == "true",
	}
	if tl := r.URL.Query().Get("tailLines"); tl != "" {
		if n, convErr := strconv.ParseInt(tl, 10, 64); convErr == nil {
			opts.TailLines = &n
		}
	}

	stream, err := k8s.OpenLogStream(r.Context(), b, r.PathValue("ns"), r.PathValue("name"), opts)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	defer stream.Close()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)

	scanner := bufio.NewScanner(stream)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		select {
		case <-r.Context().Done():
			return
		default:
		}
		w.Write([]byte("data: "))
		w.Write(scanner.Bytes())
		w.Write([]byte("\n\n"))
		flusher.Flush()
	}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/handler/ -race -v`
Expected: PASS (all handler tests, including Task 3/4 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/handler/
git commit -m "feat(handler): generic resource, action, log, and context HTTP handlers"
```

---

## Task 9: Server routes + main wiring

**Files:**
- Modify: `internal/server/server.go`
- Modify: `cmd/server/main.go`

- [ ] **Step 1: Rewrite `internal/server/server.go` route registration**

Replace the `New(...)` signature and route block (keep `Start`/`health` unchanged). New `New`:

```go
func New(port string, h handler.Handlers) *Server {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("/swagger/", httpSwagger.WrapHandler)

	mux.HandleFunc("GET /api/v1/contexts", h.Contexts.List)

	// Generic resources.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/resources", h.Resources.Apply)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/resources/{resource}", h.Resources.List)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}", h.Resources.List)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Get)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml", h.Resources.YAML)
	mux.HandleFunc("DELETE /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Delete)
	mux.HandleFunc("PATCH /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Patch)

	// Actions.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale", h.Actions.Scale)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart", h.Actions.Restart)

	// Logs (SSE).
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log", h.Logs.Stream)

	return &Server{
		http: &http.Server{
			Addr:              fmt.Sprintf(":%s", port),
			Handler:           recoverer(mux),
			ReadHeaderTimeout: 15 * time.Second,
			// No global WriteTimeout: log streaming is long-lived (§10 decision 1).
		},
	}
}
```

Add import `"github.com/hashirayaz/k67s-api/internal/handler"` (already present) and ensure `recoverer` is exported or referenced. Since `recoverer` lives in `handler`, either export it as `handler.Recoverer` or wrap in server. **Decision:** export it — rename `recoverer` → `Recoverer` in `handlers.go` and call `handler.Recoverer(mux)` here.

- [ ] **Step 2: Update `cmd/server/main.go`**

```go
package main

import (
	"log"

	_ "github.com/hashirayaz/k67s-api/docs"

	"github.com/hashirayaz/k67s-api/internal/cluster"
	"github.com/hashirayaz/k67s-api/internal/config"
	"github.com/hashirayaz/k67s-api/internal/handler"
	"github.com/hashirayaz/k67s-api/internal/server"
)

func main() {
	cfg := config.Load()

	provider, err := cluster.NewProvider(cfg.KubeconfigPath)
	if err != nil {
		log.Fatalf("cluster provider: %v", err)
	}

	srv := server.New(cfg.Port, handler.New(provider))
	if err := srv.Start(); err != nil {
		log.Fatalf("server: %v", err)
	}
}
```

- [ ] **Step 3: Verify it builds**

Run: `go build ./...`
Expected: build fails ONLY on the now-orphaned old handlers/stores referenced nowhere — proceed to Task 11 to remove them. If build is clean, even better.

- [ ] **Step 4: Commit**

```bash
git add internal/server/server.go cmd/server/main.go
git commit -m "feat(server): wire dynamic handlers and route table"
```

---

## Task 10: Rename recoverer for cross-package use

**Files:**
- Modify: `internal/handler/handlers.go`

- [ ] **Step 1: Export the middleware**

In `handlers.go`, rename `func recoverer` → `func Recoverer` and update the doc comment. Update `server.go` (Task 9) to call `handler.Recoverer(mux)`.

- [ ] **Step 2: Verify**

Run: `go vet ./internal/server/ ./internal/handler/`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add internal/handler/handlers.go internal/server/server.go
git commit -m "refactor(handler): export Recoverer middleware"
```

---

## Task 11: Migration cleanup — remove typed handlers/stores

**Files:**
- Delete: `internal/handler/pods.go`, `internal/handler/deployments.go`, `internal/handler/services.go`, `internal/handler/namespaces.go`
- Delete: `internal/k8s/pods.go`, `internal/k8s/deployments.go`, `internal/k8s/services.go`, `internal/k8s/namespaces.go`
- Delete: `internal/k8s/client.go`
- Evaluate: `internal/k8s/helpers.go` (delete if `formatAge` unused)

- [ ] **Step 1: Delete superseded files**

```bash
git rm internal/handler/pods.go internal/handler/deployments.go internal/handler/services.go internal/handler/namespaces.go
git rm internal/k8s/pods.go internal/k8s/deployments.go internal/k8s/services.go internal/k8s/namespaces.go
git rm internal/k8s/client.go
```

- [ ] **Step 2: Check for orphaned helpers**

Run: `grep -rn "formatAge\|readyContainers\|totalRestarts" internal/`
If no references remain: `git rm internal/k8s/helpers.go`. Otherwise leave it.

- [ ] **Step 3: Verify the whole build and test suite**

Run: `go build ./... && go test ./... -race`
Expected: build clean, all tests PASS.

- [ ] **Step 4: Regenerate Swagger docs**

Run: `make docs`
Expected: `docs/swagger.json`, `docs/swagger.yaml`, `docs/docs.go` regenerate with the new endpoints and no references to deleted types.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove per-resource handlers/stores superseded by dynamic backend"
```

---

## Task 12: Live integration verification

**Goal:** Prove the running API works against the real cluster (current kube-context, which includes cert-manager/ingress-nginx CRDs).

- [ ] **Step 1: Start the server**

Run (background): `go run ./cmd/server` (listens on `:8080`).

- [ ] **Step 2: Contexts + health**

```bash
curl -s localhost:8080/health
curl -s localhost:8080/api/v1/contexts | jq '.data[].name'
```
Expected: `{"status":"ok"}`; at least the current context name listed.

- [ ] **Step 3: List built-in resources (Table format)**

```bash
curl -s "localhost:8080/api/v1/contexts/_current/resources/namespaces" | jq '.data.columns[].name'
curl -s "localhost:8080/api/v1/contexts/_current/namespaces/kube-system/resources/pods" | jq '.data.rows | length'
```
Expected: column names include `Name`/`Status` etc.; pod row count > 0.

- [ ] **Step 4: List a CRD (proves dynamic coverage)**

```bash
curl -s "localhost:8080/api/v1/contexts/_current/resources/certificates.cert-manager.io" | jq '.data.columns[].name'
```
Expected: HTTP 200 with cert-manager's printer columns (e.g. `Ready`, `Secret`, `Age`) — no code change was needed for this CRD.

- [ ] **Step 5: Get + YAML round-trip**

```bash
NS=kube-system
POD=$(curl -s "localhost:8080/api/v1/contexts/_current/namespaces/$NS/resources/pods" | jq -r '.data.rows[0].object.name')
curl -s "localhost:8080/api/v1/contexts/_current/namespaces/$NS/resources/pods/$POD" | jq '.data.metadata.name'
curl -s "localhost:8080/api/v1/contexts/_current/namespaces/$NS/resources/pods/$POD/yaml" | head -3
```
Expected: object name matches; YAML output begins with `apiVersion:`.

- [ ] **Step 6: Log streaming**

```bash
curl -s -N "localhost:8080/api/v1/contexts/_current/namespaces/$NS/resources/pods/$POD/log?tailLines=5" &
sleep 2; kill %1 2>/dev/null
```
Wait — note the log route is `.../pods/{name}/log` (not under `/resources/`). Use:
```bash
curl -s -N "localhost:8080/api/v1/contexts/_current/namespaces/$NS/pods/$POD/log?tailLines=5"
```
Expected: `data: ` framed lines.

- [ ] **Step 7: Error mapping**

```bash
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/api/v1/contexts/_current/resources/widgets"
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/api/v1/contexts/_current/namespaces/$NS/resources/pods/does-not-exist"
```
Expected: `404` for both (unknown resource; not found).

- [ ] **Step 8: Scoped write test (safe namespace)**

```bash
kubectl create namespace k67s-test 2>/dev/null || true
cat <<'EOF' | curl -s -X POST --data-binary @- "localhost:8080/api/v1/contexts/_current/resources" | jq '.data.metadata.name'
apiVersion: v1
kind: ConfigMap
metadata:
  name: k67s-smoke
  namespace: k67s-test
data:
  hello: world
EOF
curl -s -X DELETE "localhost:8080/api/v1/contexts/_current/namespaces/k67s-test/resources/configmaps/k67s-smoke" | jq '.data.deleted'
kubectl delete namespace k67s-test
```
Expected: apply returns `k67s-smoke`; delete returns `k67s-smoke`.

- [ ] **Step 9: Stop the server** and record results in the PR/commit description.

---

## Self-Review Notes

- **Spec coverage:** §4 Provider → Task 1; §5 resolver → Task 2; §6.2 generic handler → Tasks 5, 8; §6.3 actions → Tasks 6, 8; §6.4 logs → Tasks 7, 8; §7 envelope/Table → Tasks 3, 8; §8 error mapping → Task 4; §9 migration → Tasks 9–11; §11 testing → unit tests per task + Task 12 live; §12 coverage table → verified by Task 12 steps 3/4/5/6.
- **Deferred per spec:** watch/informers, exec, port-forward — not in any task (correct).
- **Type consistency:** `ResourceRef{GVR, Namespaced}`, `ClientBundle{Typed,Dynamic,Discovery,Mapper}`, `Provider{Contexts,Current,Bundle}`, `Handlers{Resources,Actions,Logs,Contexts}`, `tableToPayload`, `statusFromK8sErr`, `Recoverer` used consistently across tasks.
- **Open item:** `_current` sentinel confirmed in code (Task 8 `bundleFor`); SwiftUI client alignment is a client-side follow-up, out of scope here.
