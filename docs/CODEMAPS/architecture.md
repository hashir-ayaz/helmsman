<!-- Generated: 2026-07-10 | Files scanned: 97 | Token estimate: ~750 -->

# Helmsman Architecture

## Overview

macOS-native Kubernetes cluster manager. Monorepo with three apps sharing no runtime state — only the Swift app embeds the Go API as a sidecar.

```
┌─────────────────────────────────────────────────────────────────┐
│  helmsman-frontend (SwiftUI macOS 14+)                          │
│  k67sApp → ContentView → Sidebar + ResourceList + Detail        │
│  Windows: main | logs | yaml | shell                            │
│  BackendProcess spawns bundled helmsman-api on free port        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTP JSON envelope + SSE
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  helmsman-api (Go 1.26, net/http)                               │
│  cmd/server → config → cluster.Provider → handler.* → k8s.*   │
└──────────────────────────┬──────────────────────────────────────┘
                           │ client-go (dynamic + typed)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes API (via ~/.kube/config, multi-context)             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  helmsman-landing (Next.js 16) — static marketing, no backend   │
└─────────────────────────────────────────────────────────────────┘
```

## Service Boundaries

| Package | Role | Entry |
|---------|------|-------|
| `helmsman-api` | Stateless K8s proxy; generic CRUD + actions | `cmd/server/main.go` |
| `helmsman-frontend` | MVVM UI; actor HTTP client | `k67s/k67sApp.swift` |
| `helmsman-landing` | Download/docs landing page | `app/page.tsx` |
| `build/assets/` | App icons, DMG assets | — |

## Data Flow

```
User picks context/ns/resource (AppModel)
  → ResourceListModel.load() → GET .../resources/{resource} → k8s.FetchTable
  → ResourceListModel.watch() → SSE .../watch → debounced reload (300ms)
Row select → ResourceDetailModel.loadObject() → GET .../{name}
YAML tab → ResourceDetailModel.loadYAML() → GET .../{name}/yaml
Actions → ResourceActionsModel → POST scale/restart/suspend/drain/...
Logs → LogStreamModel → SSE .../pods/{name}/log
Shell → ShellSessionModel → local kubectl exec (no API)
```

## Key Design Decisions

- **Dynamic/generic backend** — no per-resource Go code; `k8s.Resolve()` maps URL slugs → GVR
- **Context in URL** — `{ctx}` path segment (`_current` = active context); server stateless
- **Table format lists** — `Accept: application/json;as=Table` for kubectl-identical columns
- **Embedded sidecar** — packaged app bundles `helmsman-api`; stdin pipe + `HELMSMAN_PARENT_WATCH` for orphan prevention
- **Response envelope** — `{"data": ..., "error": ...}`; YAML endpoint returns raw `application/yaml`
- **No global write timeout** — supports long-lived SSE (logs, watch)

## Not Yet Implemented

- API-backed exec/shell (frontend uses local `kubectl exec` today)
- Port-forward (bidirectional streaming)
- Rollout history for StatefulSets/DaemonSets (needs ControllerRevisions)
- Resource event stream in detail panel
