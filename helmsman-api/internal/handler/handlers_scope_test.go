package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/kubernetes/scheme"
)

func TestResourceGetClusterScoped(t *testing.T) {
	ns := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "Namespace",
		"metadata": map[string]any{"name": "kube-system"},
	}}
	h := New(newFakeProvider(ns))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("resource", "namespaces")
	req.SetPathValue("name", "kube-system")
	rec := httptest.NewRecorder()
	h.Resources.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	var resp APIResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Data == nil {
		t.Fatal("expected object in data")
	}
}

func TestResourceGetNamespacedWithoutNamespace(t *testing.T) {
	cm := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "ConfigMap",
		"metadata": map[string]any{"name": "cm-1", "namespace": "default"},
	}}
	h := New(newFakeProvider(cm))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("resource", "configmaps")
	req.SetPathValue("name", "cm-1")
	rec := httptest.NewRecorder()
	h.Resources.Get(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	var resp APIResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Error == "" {
		t.Fatal("expected error message")
	}
}

func TestResourceGetClusterScopedWithNamespace(t *testing.T) {
	ns := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "Namespace",
		"metadata": map[string]any{"name": "kube-system"},
	}}
	h := New(newFakeProvider(ns))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("resource", "namespaces")
	req.SetPathValue("name", "kube-system")
	rec := httptest.NewRecorder()
	h.Resources.Get(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}

func TestResetMapperNoOpOnStaticMapper(t *testing.T) {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	b := &cluster.ClientBundle{
		Dynamic: dyn,
		Mapper:  testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme),
	}
	b.ResetMapper() // must not panic when mapper lacks Reset()
}
