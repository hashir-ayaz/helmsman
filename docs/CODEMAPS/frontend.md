<!-- Generated: 2026-07-11 | Files scanned: 102 | Token estimate: ~960 -->

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
ContentView
├── connectionPhase .connecting → spinner
├── connectionPhase .failed     → retry UI (kubeconfig/status errors)
└── connectionPhase .ready → NavigationSplitView
    ├── SidebarView (AppModel)
    │   ├── context / namespace pickers
    │   └── Overview + ResourceType list (ResourceCatalog.all)
    └── detail:
        ├── ClusterOverviewView (default) — summary cards, workload bars, warnings
        └── ResourceListView (per resource)
            ├── AppKit Table (TablePayload columns/rows)
            ├── toolbar: live-watch indicator, refresh
            ├── context menu: scale/restart/resize/pause/suspend/cancel/drain/logs/shell/yaml
            ├── bottom toast on action success (BottomToast)
            └── HSplitView → ResourceDetailView (inspected row)
                ├── Overview tab → ResourceOverview (kind-specific)
                ├── Object tab → JSONTreeView
                └── YAML tab → lazy load

Sheets/Windows: RolloutHistorySheet, ResizePVCSheet, LogWindowView, YAMLEditorWindow, ShellWindowView
```

## State Management

| ViewModel | Scope | Key duties |
|-----------|-------|------------|
| `AppModel` | App-wide | bootstrap (`/health` + `/status`), contexts, namespace, sidebar destination |
| `ClusterOverviewModel` | Overview | parallel list aggregation, summary cards, warning events |
| `ResourceListModel` | Per list | table load (generation coalescing), search, SSE watch, debounced reload |
| `ResourceDetailModel` | Per row | JSON eager, YAML lazy |
| `ResourceActionsModel` | Per list | scale/restart/resize/rollout/suspend/cancel/drain + alerts + toast |
| `RolloutHistorySheetModel` | Sheet | revision list, undo |
| `LogStreamModel` | Log window | SSE stream, 5k-line FIFO, container switch |
| `YAMLEditorModel` | YAML window | load/apply, dirty tracking |
| `ShellSessionModel` | Shell window | kubectl exec via local PTY (no API) |

## API Client

`Services/KubeAPIClient.swift` — actor singleton, `baseURL` set by `BackendProcess.configure(port:)`

| Method | Backend route |
|--------|---------------|
| `fetchStatus()` | GET `/api/v1/status` |
| `listContexts()` | GET `/api/v1/contexts` |
| `listResources(ctx,ns,resource)` | GET `.../resources/{resource}` |
| `getObject(...)` | GET `.../{name}` |
| `getYAML(...)` | GET `.../{name}/yaml` |
| `apply(ctx,yaml)` | POST `.../resources` |
| `resizePVC(...)` | POST `.../persistentvolumeclaims/{name}/resize` |
| `delete/scale/restart/suspend/...` | matching POST/DELETE/PATCH |
| `streamWatch(...)` | SSE `.../watch` (nonisolated) |
| `streamLogs(...)` | SSE `.../pods/{name}/log` (nonisolated) |

## Resource Catalog

`Models/ResourceCatalog.swift` — single source of truth for sidebar (20+ types across 5 sections).

Capability flags drive context menu: `scaleWorkload`, `restartWorkload`, `supportsPause`, `supportsSuspend`, `supportsCancel`, `supportsDrain`, `supportsResize`, `supportsCascadeDelete`, `isPods`.

Sheets: `RolloutHistorySheet`, `ResizePVCSheet`, `DeleteOptionsSheet` (cascade delete for controllers).

## Key Patterns

- **`JSONValue`** for all untyped K8s data — no per-resource Swift structs
- **`TablePayload`** mirrors backend Table format (columns + cell arrays + ObjectStub)
- **Live watch** on every list — `watch()` → `scheduleReload()` 300ms debounce
- **Table stability** — `willMutatePayload` clears AppKit selection before payload swap; `loadGeneration` coalesces concurrent loads; `onMutated` cancels pending watch reload and reloads immediately; separate `selectedRowID` vs `inspectedRowID`
- **`RowActionAlerts`** ViewModifier — confirmation dialogs, rollout sheet, resize sheet, bottom toast
- **Namespace scoping** — `AppModel.namespaceParam` nil = "All Namespaces" cluster list path

## Embedded Backend

`Services/BackendProcess.swift` — spawns bundled `helmsman-api`, picks free port, widens PATH for exec credential plugins. Dev mode (no bundle) → defaults to `:8080` + `make run`.

## Detail Overviews

Kind-specific overview components in `Views/Detail/Overviews/`; `ResourceOverview` dispatches by resource type.
