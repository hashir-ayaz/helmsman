# k67s-api — Dynamic Kubernetes Backend Design

**Date:** 2026-06-10
**Status:** Approved (Approach A)
**Module:** `github.com/hashirayaz/k67s-api`
**Stack:** Go 1.26, `k8s.io/client-go` v0.32.3, stdlib `net/http` (1.22 routing)

## 1. Goal & Scope

Scale the backend from four hardcoded read-only resource handlers to a backend that gives a SwiftUI Mac client ~80% of what k9s/Lens offer, while keeping the code small and maintainable.

### In scope (MVP)

- **Dynamic resource coverage** — every built-in resource *and* every CRD, via discovery + RESTMapper + dynamic client. No per-resource Go code to add a type.
- **Read** — list (server-side Table format), get one object, fetch raw YAML.
- **Mutate** — apply/replace YAML, delete, patch, plus the typed actions `scale` and `rollout restart`.
- **Log streaming** — follow container logs over SSE.
- **Multi-context** — enumerate kubeconfig contexts and switch the active cluster per request.

### Non-goals (deferred, but designed not to block)

- Server-side watch/informers (MVP uses **client polling**).
- `exec` and `port-forward` (bidirectional WebSocket/SPDY).
- Per-resource server-side "renderers" beyond the Table API (Approach B).
- AuthN/AuthZ beyond the user's own kubeconfig (the backend runs locally as the user).

## 2. Guiding Principle

> A pod, a Deployment, and an Istio `VirtualService` are all just a `(group, version, resource)` tuple carrying an unstructured object.

Therefore: **one generic CRUD/YAML handler keyed on GVR**, plus a **small set of action handlers** for operations that don't generalize (`scale`, `rollout restart`, `logs`). The current typed `PodSummary`/`DeploymentSummary` structs are retired in favour of the API server's **Server-Side Table** output (`Accept: application/json;as=Table;g=meta.k8s.io;v=v1`), which yields kubectl-identical columns for any resource — including CRDs that advertise `additionalPrinterColumns`.

## 3. Architecture Overview

```
cmd/server/main.go
  └─ wires config → ClientProvider → handlers → server

internal/
  config/        Config (adds nothing new; KUBECONFIG already handled)
  cluster/       NEW. ClientProvider: per-context cached clientsets + GVR resolution
  k8s/           Resource access layer (dynamic-first)
    provider.go    context discovery + cached client bundles
    resolver.go    GVR/GVK resolution via RESTMapper + discovery
    resources.go   generic list/get/apply/delete/patch over dynamic client
    actions.go     scale, rollout restart
    logs.go        pod log streaming
    helpers.go     (existing) formatAge etc. — mostly unused after Table API
  handler/
    response.go    (existing envelope, extended — see §7)
    resources.go   NEW. generic ResourceHandler (CRUD/YAML)
    actions.go     NEW. ActionHandler (scale, restart)
    logs.go        NEW. LogHandler (SSE)
    contexts.go    NEW. ContextHandler (list/switch contexts)
    middleware.go  NEW. context resolution, panic recovery
  server/
    server.go      route registration (generic + action routes)
```

The existing `internal/k8s/{pods,deployments,services,namespaces}.go` and `internal/handler/{pods,deployments,services,namespaces}.go` are **removed** — their behaviour is subsumed by the generic list path. (See §9 migration.)

## 4. Cluster & Context Layer (`cluster.ClientProvider`)

The current `k8s.NewClient` builds one clientset at startup. We replace it with a provider that lazily builds and caches a **client bundle per kubeconfig context**.

```go
// ClientBundle holds everything a handler needs for one cluster context.
type ClientBundle struct {
    Typed     kubernetes.Interface       // typed client — pod logs, scale subresource
    Dynamic   dynamic.Interface          // unstructured CRUD over any GVR
    Mapper    meta.RESTMapper            // GVK <-> GVR, namespaced-ness
    Discovery discovery.DiscoveryInterface
}

type ClientProvider interface {
    // Contexts returns the contexts found in the loaded kubeconfig.
    Contexts() []ContextInfo
    // Current returns the default/active context name.
    Current() string
    // Bundle returns (building + caching) the client bundle for a context.
    Bundle(contextName string) (*ClientBundle, error)
}
```

Design notes:

- Built from `clientcmd` loading rules (respects `KUBECONFIG`, falls back to `~/.kube/config`). In-cluster config is kept as a single synthetic context named `in-cluster` for parity with today's behaviour.
- The `RESTMapper` is a `restmapper.DeferredDiscoveryRESTMapper` backed by a memory-cached discovery client. It is **reset on `meta.NoResourceMatchError`** so newly-installed CRDs become resolvable without a restart.
- Bundles are cached in a `map[string]*ClientBundle` guarded by a `sync.RWMutex`. Immutable once built. Cache key = context name.
- `ContextInfo` = `{ Name, Cluster, Namespace, IsCurrent }`, derived from kubeconfig — enough for the UI to render a context switcher.

## 5. GVR Resolution (`k8s.resolver`)

The URL carries a human/REST-friendly resource identifier; the resolver turns it into the GVR the dynamic client needs and tells us whether it's namespaced.

```go
type ResourceRef struct {
    GVR        schema.GroupVersionResource
    Namespaced bool
}

// Resolve turns a URL path identifier into a concrete GVR.
//   "pods"                              -> core/v1 pods
//   "deployments" / "deployments.apps"  -> apps/v1 deployments
//   "virtualservices.networking.istio.io" -> CRD GVR
func (r *Resolver) Resolve(resourceParam string) (ResourceRef, error)
```

- Accepts `resource` or `resource.group` (e.g. `deployments.apps`) — same grammar kubectl accepts. This avoids ambiguity when two groups expose the same resource name.
- Backed by the bundle's `RESTMapper`. Namespaced-ness comes from the mapping, which decides whether we use `.Namespace(ns).` on the dynamic client.
- Unknown resource → `404` with a clear message (`unknown resource "widgets": no matches for kind in cluster`).

## 6. HTTP Surface

### 6.1 Route scheme

Context is a path segment so the UI can pin a request to a cluster without shared mutable server state (keeps the backend stateless → polling-friendly):

```
# Cluster / context
GET    /api/v1/contexts                          list contexts + current
GET    /health                                   unchanged

# Generic resources (the workhorse) — {resource} may be "kind" or "kind.group"
GET    /api/v1/contexts/{ctx}/resources/{resource}                       cluster-scoped list (Table)
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}       namespaced list (Table)
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}        get one (object)
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml   get raw YAML
POST   /api/v1/contexts/{ctx}/resources                                  apply YAML (server-side apply)
DELETE /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}        delete
PATCH  /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}        patch (merge/json)

# Typed actions (don't generalize)
POST   /api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale            {"replicas": N}
POST   /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart           rollout restart
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log                     stream logs (SSE)
```

Cluster-scoped resources (Namespace, Node, PV, ClusterRole, …) use the `…/resources/{resource}` form without a namespace segment; the resolver rejects a namespaced resource requested without a namespace and vice-versa.

`{ctx}` may be omitted by the client by using the literal `_current` to mean "active context" — convenience so the UI doesn't have to resolve the context name first.

### 6.2 Generic `ResourceHandler`

One handler, methods per verb, all flowing through resolve → dynamic/typed call → envelope:

```go
type ResourceHandler struct{ provider cluster.ClientProvider }

func (h *ResourceHandler) List(w, r)   // Table API; returns columns + rows
func (h *ResourceHandler) Get(w, r)    // unstructured object
func (h *ResourceHandler) YAML(w, r)   // sigs.k8s.io/yaml marshal of the object
func (h *ResourceHandler) Apply(w, r)  // parse YAML -> GVK -> server-side apply
func (h *ResourceHandler) Delete(w, r)
func (h *ResourceHandler) Patch(w, r)
```

**List** sets `ListOptions`-equivalent on the dynamic/REST client requesting `as=Table` and returns a `metav1.Table`. The handler reshapes it into the response (§7). Query params `?labelSelector=` and `?fieldSelector=` pass through.

**Apply** reads YAML from the body, decodes to `unstructured.Unstructured` (capturing its embedded GVK), resolves the GVR from that GVK, and performs a server-side apply (`Patch` with `types.ApplyPatchType`, `FieldManager: "k67s"`). This is how "edit YAML and save" round-trips from the UI.

### 6.3 `ActionHandler`

```go
func (h *ActionHandler) Scale(w, r)    // updates scale subresource via typed client
func (h *ActionHandler) Restart(w, r)  // patches spec.template annotation
                                       //   kubectl.kubernetes.io/restartedAt=<RFC3339>
```

`Restart` accepts `{workload}` ∈ {deployments, statefulsets, daemonsets} and patches the pod-template annotation — the same mechanism `kubectl rollout restart` uses. Timestamp is supplied via the request (the backend forbids `Date.now()` in this harness; the SwiftUI client sends `restartedAt`, or the handler reads it from a request header) to keep behaviour deterministic and testable.

### 6.4 `LogHandler` (SSE)

```go
func (h *LogHandler) Stream(w, r)
```

- Opens `CoreV1().Pods(ns).GetLogs(name, &PodLogOptions{Follow: follow, Container: c, TailLines: n})`.
- Sets `Content-Type: text/event-stream`, flushes each line as `data: <line>\n\n`.
- Honours `r.Context()` cancellation (client disconnect) and a write deadline; closes the upstream stream on return.
- Query params: `?container=`, `?follow=true|false`, `?tailLines=`, `?previous=true`.
- **Note:** the server's global `WriteTimeout: 15s` (server.go) breaks long-lived streams. The log route is served by a second `http.Server`/handler configuration with `WriteTimeout: 0`, or we drop the global write timeout and enforce per-handler deadlines. Decision recorded in §10.

## 7. Response Envelope

Keep the existing `APIResponse{ Data, Error }` shape — the SwiftUI client already depends on it — and standardize two `Data` payload shapes.

```go
// List payload (Table-driven): columns are server-defined, rows are generic.
type TablePayload struct {
    Columns []TableColumn `json:"columns"` // {name, type, priority}
    Rows    []TableRow    `json:"rows"`    // {cells:[...], object:{namespace,name,uid}}
}

// Object payload: the raw unstructured object's .Object map (get) or YAML string (yaml).
```

- `writeSuccess` / `writeError` stay as-is. Add `writeStatus(w, status, data)` so non-200 successes (e.g. `201 Created` on apply) and richer error bodies are possible without breaking the envelope.
- Each `TableRow` includes a minimal `object` stub (`namespace`, `name`, `uid`) so the client can build the follow-up get/delete/yaml URLs without parsing cells.

## 8. Error Handling & RBAC

K8s API errors carry structured status. Map them rather than collapsing everything to 500:

```go
func statusFromK8sErr(err error) (code int, msg string) {
    switch {
    case apierrors.IsNotFound(err):      return 404, ...
    case apierrors.IsForbidden(err):     return 403, "RBAC: <reason>"  // surface to UI
    case apierrors.IsConflict(err):      return 409, ...
    case apierrors.IsInvalid(err):       return 422, ...   // bad YAML / validation
    case meta.IsNoMatchError(err):       return 404, "unknown resource ..."
    default:                             return 500, "internal error"
    }
}
```

- **Forbidden is first-class.** A read-only / namespace-scoped kubeconfig is normal; the UI must show "you don't have permission" rather than a generic failure.
- Internal details are logged server-side (`log` package, as today); the client message is sanitized.
- A `recover` middleware converts panics into `500` + log entry so one bad resource can't crash the server.

## 9. Migration From Current Code

1. Add `cluster` package + `k8s` dynamic layer alongside existing code (no break yet).
2. Add generic `ResourceHandler` + routes; verify it reproduces the existing four list endpoints' data via Table API.
3. Point `main.go` at the `ClientProvider`; register generic + action + log routes.
4. **Delete** `handler/{pods,deployments,services,namespaces}.go`, `k8s/{pods,deployments,services,namespaces}.go`, and the now-unused summary structs. Keep `helpers.go` only if `formatAge` is still referenced (Table API likely makes it dead → remove).
5. Update `internal/server/server.go` `New(...)` signature: it now takes the handler set (`ResourceHandler`, `ActionHandler`, `LogHandler`, `ContextHandler`) instead of four typed handlers.
6. Update Swagger annotations: the generic endpoints document `resource` as a path param; the four old per-resource doc blocks go away.

Old routes (`/api/v1/pods`, `/api/v1/namespaces/{ns}/pods`, …) are **removed outright** — clean cutover. The SwiftUI client migrates to the generic routes in the same change; no aliases are kept.

## 10. Open Decisions

1. **Log streaming timeout** — drop global `WriteTimeout` and enforce per-handler deadlines, *or* run a separate listener for streaming routes. Leaning: drop global write timeout, add explicit deadlines to non-streaming handlers via middleware. (Low risk for a localhost dev tool.)
2. **`_current` context sentinel** — confirm the SwiftUI client is happy resolving context client-side vs. relying on the sentinel.

**Resolved:** Legacy route aliases — *clean cutover*, old per-resource routes removed outright; Swift client migrates in lockstep (see §9).

## 11. Testing Strategy

- **Resolver / provider unit tests** with `fake` discovery + `testrestmapper`: resource-string parsing, namespaced-ness, CRD resolution, NoMatch reset.
- **Handler tests** using `k8s.io/client-go/dynamic/fake` and `k8s.io/client-go/kubernetes/fake`: list reshaping, apply round-trip, delete, scale, restart annotation, error→status mapping. Table-driven, `-race`.
- **Log handler** test: fake clientset log stream → assert SSE framing and context-cancellation cleanup.
- **No live-cluster requirement** for CI; an optional `//go:build integration` suite can run against `kind` locally.
- Target ≥80% coverage on `handler` and `k8s`/`cluster` packages.

## 12. Coverage Check — Does This Hit 80% of k9s?

| k9s capability | Covered by | MVP? |
|---|---|---|
| Browse any resource type incl. CRDs | generic list (Table API) | ✅ |
| View object details / YAML | get + yaml | ✅ |
| Edit & apply YAML | server-side apply | ✅ |
| Delete | delete | ✅ |
| Scale workloads | scale action | ✅ |
| Rollout restart | restart action | ✅ |
| Tail logs | SSE log stream | ✅ |
| Namespace / context switching | contexts + path scoping | ✅ |
| Label/field filtering | list query params | ✅ |
| Live auto-refresh | client polling | ⚠️ polling, not watch |
| Shell into pod (`exec`) | — | ❌ deferred |
| Port-forward | — | ❌ deferred |

Everything except live-watch, exec, and port-forward is in MVP. That comfortably clears the 80% bar for day-to-day developer interaction.
