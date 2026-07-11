<!-- Generated: 2026-07-10 | Files scanned: 97 | Token estimate: ~900 -->

# Frontend Architecture

## Stack

Swift 6 · SwiftUI · macOS 14+ · MVVM with `@Observable` · `KubeAPIClient` actor

## App Entry & Windows

```
k67sApp
├── WindowGroup (main)     → ContentView
├── WindowGroup "logs"     → LogWindowView(LogWindowTarget)
├── WindowGroup "yaml"     → YAMLEditorWindow(YAMLWindowTarget)
└── WindowGroup "shell"    → ShellWindowView(ShellWindowTarget)

AppDelegate → BackendProcess.start/stop (embedded sidecar lifecycle)
```

## View Hierarchy

```
ContentView (NavigationSplitView)
├── SidebarView (AppModel)
│   ├── context picker
│   ├── namespace picker
│   └── ResourceType list (ResourceCatalog.all)
└── ResourceListView (per selected ResourceType)
    ├── Table (TablePayload columns/rows from backend)
    ├── toolbar: live-watch indicator, refresh
    ├── context menu: scale/restart/pause/suspend/cancel/drain/logs/shell/yaml
    └── HSplitView detail → ResourceDetailView (selected row)
        ├── Overview tab → ResourceOverview (kind-specific)
        │   ├── PodOverview, WorkloadOverview, NodeOverview
        │   ├── ServiceOverview, ConfigOverview, BatchOverview
        │   └── GenericOverview (fallback)
        ├── Object tab → JSONTreeView
        └── YAML tab → lazy load

Sheets/Windows (via openWindow):
  RolloutHistorySheet, LogWindowView, YAMLEditorWindow, ShellWindowView
```

## State Management

| ViewModel | Scope | Key duties |
|-----------|-------|------------|
| `AppModel` | App-wide | contexts, namespace, selected resource, bootstrap |
| `ResourceListModel` | Per list | table load, search filter, SSE watch, debounced reload |
| `ResourceDetailModel` | Per row | JSON eager, YAML lazy |
| `ResourceActionsModel` | Per list | scale/restart/rollout/suspend/cancel/drain + alerts |
| `RolloutHistorySheetModel` | Sheet | revision list, undo |
| `LogStreamModel` | Log window | SSE stream, 5k-line FIFO, container switch |
| `YAMLEditorModel` | YAML window | load/apply, dirty tracking |
| `ShellSessionModel` | Shell window | kubectl exec via local PTY (no API) |

## API Client

`Services/KubeAPIClient.swift` — actor singleton, `baseURL` set by `BackendProcess.configure(port:)`

| Method | Backend route |
|--------|---------------|
| `listContexts()` | GET `/api/v1/contexts` |
| `listResources(ctx,ns,resource)` | GET `.../resources/{resource}` |
| `getObject(...)` | GET `.../{name}` |
| `getYAML(...)` | GET `.../{name}/yaml` |
| `apply(ctx,yaml)` | POST `.../resources` |
| `delete/scale/restart/suspend/...` | matching POST/DELETE/PATCH |
| `streamWatch(...)` | SSE `.../watch` (nonisolated) |
| `streamLogs(...)` | SSE `.../pods/{name}/log` (nonisolated) |

## Resource Catalog

`Models/ResourceCatalog.swift` — single source of truth for sidebar (20 types across 5 sections).

Capability flags drive context menu: `scaleWorkload`, `restartWorkload`, `supportsPause`, `supportsSuspend`, `supportsCancel`, `supportsDrain`, `isPods`.

## Key Patterns

- **`JSONValue`** for all untyped K8s data — no per-resource Swift structs
- **`TablePayload`** mirrors backend Table format (columns + cell arrays + ObjectStub)
- **Live watch** on every list — `watch()` → `scheduleReload()` 300ms debounce
- **`RowActionAlerts`** ViewModifier — confirmation dialogs + rollout sheet
- **Namespace scoping** — `AppModel.namespaceParam` nil = "All Namespaces" cluster list path

## Embedded Backend

`Services/BackendProcess.swift` — spawns bundled `helmsman-api`, picks free port, widens PATH for exec credential plugins. Dev mode (no bundle) → defaults to `:8080` + `make run`.

## Detail Overviews

Kind-specific overview components in `Views/Detail/Overviews/`; `ResourceOverview` dispatches by resource type.
