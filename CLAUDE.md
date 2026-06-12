# Helmsman (k67s)

A macOS-native Kubernetes cluster manager. Two repos live here:

- `k67s-api/` — Go backend that talks to Kubernetes via kubeconfig
- `k67s/` — SwiftUI macOS frontend that talks to the Go backend

---

## Running the project

**Backend (required first):**
```bash
cd k67s-api
make run          # go run ./cmd/server — listens on :8080
make build        # go build -o bin/k67s-api ./cmd/server
make docs         # regenerate swagger via swaggo/swag
make tidy         # go mod tidy
```

Config is env-based: `PORT` (default `8080`), `KUBECONFIG` (default `~/.kube/config`).

**Frontend:**
Open `k67s/k67s/k67s.xcodeproj` in Xcode and run. The app expects the backend on `http://localhost:8080` (hardcoded in `KubeAPIClient.swift`).

---

## Backend (`k67s-api`)

**Stack:** Go 1.26, stdlib `net/http` (1.22 routing), `k8s.io/client-go` v0.32.3, `sigs.k8s.io/yaml`, `swaggo/swag`  
**Module:** `github.com/hashirayaz/k67s-api`

### Package layout

```
cmd/server/main.go          entry point — wires config → provider → handlers → server
internal/
  config/config.go          env-based config (PORT, KUBECONFIG)
  cluster/provider.go       multi-context ClientBundle (lazy, cached, sync.RWMutex)
  k8s/
    resolver.go             URL slug → GVR/GVK via RESTMapper
    resources.go            generic CRUD: list (Table), get, YAML, delete, patch, apply
    actions.go              scale (replica patch), restart (pod-template annotation)
    logs.go                 pod log stream (io.ReadCloser)
  handler/
    handlers.go             Handlers aggregate + bundleAndRef helper + Recoverer middleware
    resources.go            ResourceHandler (List, Get, YAML, Apply, Delete, Patch)
    actions.go              ActionHandler (Scale, Restart)
    logs.go                 LogHandler (SSE)
    contexts.go             ContextHandler (list kubeconfig contexts)
    response.go             writeSuccess / writeError / writeStatus envelope
    table.go                metav1.Table → TablePayload
    errors.go               statusFromK8sErr — maps k8s API errors to HTTP codes
  server/server.go          route registration, graceful shutdown
docs/                       swagger (generated — do not edit by hand)
```

### HTTP routes

```
GET    /health
GET    /swagger/

GET    /api/v1/contexts
POST   /api/v1/contexts/{ctx}/resources                                        apply YAML (server-side apply)
GET    /api/v1/contexts/{ctx}/resources/{resource}                             cluster-scoped list (Table)
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}             namespaced list (Table)
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}      get one object
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml get YAML
DELETE /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}
PATCH  /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}      merge patch
POST   /api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale         {"replicas": N}
POST   /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart        {"restartedAt": "<RFC3339>"}
GET    /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log                  SSE log stream
```

`{ctx}` = context name or `_current` (active context). `{resource}` = `pods`, `deployments.apps`, `virtualservices.networking.istio.io`, etc.

### Key design decisions

**Dynamic/generic by default.** There is no per-resource Go code. Every resource (including CRDs) flows through `k8s.Resolve()` → `GVR` → dynamic client. To add a new resource you only add it to the Swift `ResourceCatalog.swift` — the backend needs no changes.

**Server-side Table format.** List calls use `Accept: application/json;as=Table;v=v1;g=meta.k8s.io` which returns kubectl-identical columns for any resource, including CRDs with `additionalPrinterColumns`.

**Context in URL path.** `{ctx}` as a path segment keeps the server stateless. Bundles are lazy-built and cached in `cluster.Provider` behind a read/write mutex.

**Response envelope.** All JSON responses: `{"data": ..., "error": ...}`. The YAML endpoint returns raw `application/yaml`.

**Error mapping.** `statusFromK8sErr` maps k8s API errors to HTTP codes. 403 (RBAC forbidden) is first-class — surfaced distinctly so the UI can show "you don't have permission" rather than a generic failure.

**Restart mechanism.** Uses the same patch as `kubectl rollout restart` — stamps `kubectl.kubernetes.io/restartedAt` on the pod-template annotation. The timestamp is caller-supplied (Swift client sends `restartedAt`) to keep it deterministic.

**No global write timeout.** Dropped to support long-lived log SSE streams. Per-handler deadlines are the intended approach for non-streaming routes.

### Adding a new action

Actions that don't fit the generic CRUD pattern (like scale and restart) get their own handler method in `handler/actions.go` and their own `k8s/` function. Register the route in `server/server.go`.

---

## Frontend (`k67s`)

**Stack:** Swift 6, SwiftUI, macOS 14+  
**Architecture:** MVVM with `@Observable` ViewModels and an `actor`-based API client

### File layout

```
k67sApp.swift               3 windows: main, "logs", "yaml"
ContentView.swift           root — NavigationSplitView (sidebar + list)
Models/
  ResourceCatalog.swift     ResourceType catalog + ResourceSection enum — edit here to add sidebar items
  TablePayload.swift        decoded backend table: columns, rows, object stubs
  JSONValue.swift           flexible recursive JSON type for heterogeneous K8s fields
  APIResponse.swift         envelope decoder + APIError enum
  ContextInfo.swift         kubeconfig context info
  LogWindowTarget.swift     Codable window identity for log windows
  YAMLWindowTarget.swift    Codable window identity for YAML editor windows
  Collection+Safe.swift     safe subscript extension [safe:]
Services/
  KubeAPIClient.swift       actor singleton — all HTTP calls; baseURL = http://localhost:8080
ViewModels/
  AppModel.swift            app-wide state: contexts, namespace, selected resource
  ResourceListModel.swift   table loading, search, column visibility, status color derivation
  ResourceDetailModel.swift single object: JSON (eager) + YAML (lazy, only on tab switch)
  ResourceActionsModel.swift scale/restart/delete modal coordination (@MainActor)
  LogStreamModel.swift      SSE streaming, 5000-line FIFO buffer, per-container switching
  YAMLEditorModel.swift     YAML load + apply, dirty tracking
Views/
  SidebarView.swift         context/namespace pickers + resource type list
  ResourceListView.swift    generic Table view — reused for all resource types
  ResourceDetailView.swift  detail panel: Overview / Object (JSON tree) / YAML tabs
  LogWindowView.swift       log streaming window
  YAMLEditorWindow.swift    YAML editor with ⌘S to apply
  Components/
    StatusDot.swift         colored dot + ResourceColors.statusColor(_:)
    JSONTreeView.swift      collapsible JSON tree
    CodeEditorView.swift    NSTextView wrapper for code editing
    PortChipsView.swift     port number chips (Services "Port(s)" column)
    ErrorStateView.swift    error banner with retry button
    RowActionAlerts.swift   scale/restart/delete confirmation alerts
```

### Key patterns

**`@Observable` ViewModels.** All ViewModels use `@Observable` (not `ObservableObject`). Just mutate properties directly — no `@Published` needed.

**`KubeAPIClient` is a Swift actor.** Call `KubeAPIClient.shared` from async contexts. The `streamLogs` method is `nonisolated` (long-lived SSE, never hops the actor per line).

**`ResourceType` catalog.** The single source of truth for what appears in the sidebar. To add a resource: add an entry to `ResourceType.all` in `ResourceCatalog.swift`. The backend needs no changes — it's fully dynamic.

**`JSONValue` for everything untyped.** K8s objects and table cells are decoded as `JSONValue`. Use subscript access: `object["metadata"]?["name"]?.stringValue`. Do not introduce typed structs for specific K8s resource fields.

**`TablePayload` mirrors the backend exactly.** Columns are server-defined (`priority == 0` = always shown, `> 0` = wide). Rows carry heterogeneous `cells: [JSONValue]` aligned 1:1 with columns, plus an `ObjectStub` for follow-up URL building.

**Window management.** Log and YAML windows are opened via `@Environment(\.openWindow)` with `Codable` target values (`LogWindowTarget`, `YAMLWindowTarget`). The window group IDs are `"logs"` and `"yaml"`.

**Log streaming.** Uses `AsyncThrowingStream<String, Error>` over URLSession bytes. Buffer is capped at 5,000 lines (FIFO). Container switching calls `restart()` which restarts the stream task.

**Status colors.** Centralized in `ResourceColors.statusColor(_:)` in `StatusDot.swift`. Add new status strings there.

**Detail view loading.** JSON object loads eagerly on row selection. YAML loads lazily — only when the YAML tab is first tapped (guarded by `guard yaml == nil`).

**Namespace scoping.** `AppModel.namespaceParam` is `nil` for "All Namespaces" (cluster-scoped list path) and the namespace string otherwise. Cluster-scoped resources (`scope == .cluster`) always pass `nil` regardless.

---

## What is not yet implemented

- `exec` / shell into pod (requires WebSocket/SPDY)
- Port-forward (requires bidirectional streaming)
- Server-sent watch / live auto-refresh (currently client polling via `.task(id:)`)

---

## Tests

**Backend:**
```bash
cd k67s-api
go test -race ./...
go test -cover ./...
```

Test files use `k8s.io/client-go/dynamic/fake` and `k8s.io/client-go/kubernetes/fake` — no live cluster needed.

**Frontend:** No test targets exist yet. Integration tests would use Swift Testing (`import Testing`) with protocol-based mocks injected via `KubeAPIClient` constructor.
