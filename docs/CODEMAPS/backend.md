<!-- Generated: 2026-07-10 | Files scanned: 97 | Token estimate: ~950 -->

# Backend Architecture

## Stack

Go 1.26 · stdlib `net/http` (1.22 routing) · `k8s.io/client-go` v0.32.3 · swaggo/swagger

## Boot Chain

```
main.go → config.Load() → cluster.NewProvider(KUBECONFIG)
       → handler.New(provider) → server.New(port, handlers) → Start()
```

## Package Map

| Path | Responsibility |
|------|----------------|
| `cmd/server/main.go` | Entry; parent-death watcher for sidecar mode |
| `internal/config/config.go` | `PORT` (8080), `KUBECONFIG` (~/.kube/config) |
| `internal/cluster/provider.go` | Lazy per-context `ClientBundle` cache (RWMutex) |
| `internal/k8s/resolver.go` | URL slug → `ResourceRef` (GVR/GVK) via RESTMapper |
| `internal/k8s/resources.go` | List (Table), Get, YAML, Delete, Patch, Apply |
| `internal/k8s/actions.go` | Scale, Restart, SetSuspend, CancelJob |
| `internal/k8s/rollout.go` | History, Undo, Pause, Resume (Deployment RS inspection) |
| `internal/k8s/drain.go` | Cordon + evict (skip DaemonSet/mirror pods) |
| `internal/k8s/watch.go` | Goroutine watch channel, reconnect, 410 Gone handling |
| `internal/k8s/logs.go` | Pod log stream (`io.ReadCloser`) |
| `internal/handler/*.go` | HTTP handlers, envelope, Table conversion, SSE |
| `internal/server/server.go` | Route registration, graceful shutdown |

## Routes

```
GET  /health
GET  /swagger/

GET  /api/v1/contexts
     → ContextHandler.List → provider.Contexts()

POST /api/v1/contexts/{ctx}/resources
     → ResourceHandler.Apply → k8s.ParseManifest + k8s.Apply

GET  /api/v1/contexts/{ctx}/resources/{resource}
GET  /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}
     → ResourceHandler.List → k8s.FetchTable

GET  /api/v1/contexts/{ctx}/[namespaces/{ns}/]resources/{resource}/{name}
     → ResourceHandler.Get → k8s.Get
GET  .../yaml → ResourceHandler.YAML → k8s.YAML
DELETE ...    → ResourceHandler.Delete → k8s.Delete
PATCH ...     → ResourceHandler.Patch → k8s.Patch

POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/scale
     → ActionHandler.Scale → k8s.Scale
POST .../restart → ActionHandler.Restart → k8s.Restart
POST .../suspend|/resume → ActionHandler → k8s.SetSuspend
POST .../jobs/{name}/cancel → ActionHandler.CancelJob
POST /api/v1/contexts/{ctx}/nodes/{name}/drain → ActionHandler.DrainNode

GET  /api/v1/contexts/{ctx}/[namespaces/{ns}/]resources/{resource}/watch
     → WatchHandler.Stream (SSE) → k8s.Watch

GET  /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/history
POST .../rollout/undo|pause|resume → RolloutHandler → k8s.Rollout*

GET  /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log
     → LogHandler.Stream (SSE) → k8s.OpenLogStream
```

`{ctx}` = context name or `_current`. `{resource}` = `pods`, `deployments.apps`, etc.

## Middleware

```
Request → handler.Recoverer (panic → 500) → route handler
```

No auth middleware — relies on kubeconfig credentials and cluster RBAC.

## Handler → k8s Mapping

| Handler | k8s function |
|---------|--------------|
| `ResourceHandler.List` | `FetchTable` |
| `ResourceHandler.Get` | `Get` |
| `ResourceHandler.YAML` | `YAML` |
| `ResourceHandler.Apply` | `ParseManifest`, `Apply` |
| `ActionHandler.Scale` | `Scale` |
| `ActionHandler.Restart` | `Restart` |
| `ActionHandler.Suspend/Resume` | `SetSuspend` |
| `ActionHandler.CancelJob` | `CancelJob` |
| `ActionHandler.DrainNode` | `DrainNode` |
| `RolloutHandler.*` | `RolloutHistory/Undo/Pause/Resume` |
| `WatchHandler.Stream` | `Watch` |
| `LogHandler.Stream` | `OpenLogStream` |

## Error Handling

`handler.statusFromK8sErr` maps k8s API errors → HTTP status (403 RBAC first-class).

## Tests

`go test -race ./...` — uses `dynamic/fake` and `kubernetes/fake`; no live cluster.
