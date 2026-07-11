<!-- Generated: 2026-07-11 | Files scanned: 102 | Token estimate: ~430 -->

# Data Architecture

## Summary

Helmsman has **no application database**. All persistent state lives in the user's kubeconfig and the target Kubernetes cluster(s).

## Data Stores

| Store | Location | Used by | Contents |
|-------|----------|---------|----------|
| kubeconfig | `~/.kube/config` (or `KUBECONFIG`) | helmsman-api | contexts, clusters, users, credentials |
| Kubernetes API | cluster endpoint per context | helmsman-api | all K8s resources (source of truth) |
| In-memory cache | `cluster.Provider` (Go) | helmsman-api | per-context `ClientBundle` (clients + RESTMapper) |
| UI state | Swift `@Observable` ViewModels | frontend | ephemeral selection, table payloads, streams |
| User defaults | macOS (minimal) | frontend | none significant in codebase |

## Data Models (API contract)

### Envelope (JSON endpoints)

```json
{ "data": <T>, "error": "<string|null>" }
```

### ClusterStatus (`GET /api/v1/status`)

```
{ ready: bool, code: string, message: string }
```

Codes include kubeconfig missing/unreadable and context resolution failures.

### TablePayload (list responses)

```
columns: [{ name, type, priority, description }]
rows: [{ cells: [JSONValue], object: { name, namespace, apiVersion, kind } }]
```

### ContextInfo

```
{ name, cluster, namespace, isCurrent }
```

### WatchEvent (SSE)

```
{ type: ADDED|MODIFIED|DELETED, name, namespace }
```

### RevisionEntry (rollout history)

```
{ revision, replicas, images[], createdAt }
```

### PVC resize request

```
POST .../persistentvolumeclaims/{name}/resize
{ "storage": "10Gi" }
```

## Migrations

None — no SQL/schema. API evolution is backward-compatible route additions.

## External Data Dependencies

- **Supabase Storage** (landing only) — hosts `Helmsman.dmg` download URL
- **Homebrew tap** — `hashir-ayaz/helmsman` cask distribution (referenced on landing page)
