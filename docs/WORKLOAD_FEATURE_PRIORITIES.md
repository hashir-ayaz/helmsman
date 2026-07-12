# Workload & Networking Feature Priorities

Prioritized backlog for Helmsman, ranked by how often operators need each feature and how much they would otherwise fall back to kubectl / Lens / k9s.

**Scope today:**
- **Workloads** — Pods, Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs
- **Networking** — Services, Ingresses, NetworkPolicies, Endpoints (+ modern gaps like EndpointSlices)

**Recommended next sprint (highest ROI):** workload P1 item 7 (API-backed exec). P1 #6 and #8 are shipped.

**Architectural bets to schedule separately:** API-backed exec (streaming complexity).

---

## Workloads

### P0 — Weekly pain

*All items shipped — see **Shipped detail** and **Current baseline** below.*

| # | Feature | Status |
|---|---------|--------|
| 1 | **Owner → Pods navigation** | Shipped |
| 2 | **CronJob “Trigger now”** | Shipped |
| 3 | **Force delete** | Shipped |
| 4 | **Related events on all workloads** | Shipped |

### P1 — Core ops parity (next tier)

| # | Feature | Status |
|---|---------|--------|
| 5 | **Port-forward** | Shipped (when present on branch) |
| 6 | **Real StatefulSet / DaemonSet rollout history** | Shipped — ControllerRevisions + undo |
| 7 | **API-backed pod exec** (or reliable bundled kubectl path) | Open |
| 8 | **Cascade delete options** | Shipped — Delete with Options sheet |

#### Shipped detail (P1 #6, #8)

| # | Feature | Implementation |
|---|---------|----------------|
| 6 | **Real StatefulSet / DaemonSet rollout history** | Backend `k8s.RolloutHistory` / `RolloutUndo` dispatch by workload kind: Deployments use label-scoped ReplicaSet listing; StatefulSets and DaemonSets list owned `controllerrevisions` via `spec.selector` labelSelector and undo via strategic merge patch of `ControllerRevision.data`. Same routes `GET/POST .../rollout/{history,undo}`. Pause/resume remains Deployment-only (400 for other kinds). Frontend: existing Rollout History sheet; improved empty state and undo footnote (PVC / OnDelete caveats). |
| 8 | **Cascade delete options** | Backend: existing `DELETE` with `propagationPolicy=Foreground|Background|Orphan` query param (swagger documented). Frontend: `supportsCascadeDelete` on Deployments, STS, DS, RS, Jobs, CronJobs; context menu **Delete with Options…** opens `DeleteOptionsSheet` (cascade picker + optional grace period 0). Default **Delete** and **Force Delete…** unchanged. |

### P2 — Strong polish (after P0–P1)

| # | Feature | Why it matters |
|---|---------|----------------|
| 9 | **Logs from controllers** | “Logs for this Deployment” (aggregate / pick owned pods), same pattern Jobs already use. |
| 10 | **StatefulSet scale warnings + PVC retention visibility** | Prevent accidental data-loss on scale/delete. |
| 11 | **Live CPU/mem metrics** | metrics-server integration; nice Lens parity, not required for lifecycle ops. |
| 12 | **Label/annotation quick edit** | YAML apply already works; dedicated edit is convenience. |

### P3 — Power-user / later

| # | Feature | Notes |
|---|---------|-------|
| 13 | Ephemeral debug containers | Growing standard; not daily for most teams. |
| 14 | `kubectl cp` / attach | Occasional power-user needs. |
| 15 | HPA / PDB deep-links from workloads | Convenience navigation. |
| 16 | ReplicaSet orphan/adopt | Rare admin task. |

### Current baseline (already shipped)

Specialized actions beyond generic CRUD (list / get / YAML / delete / patch / apply / watch):

| Resource | Specialized actions |
|----------|---------------------|
| **Pods** | Logs (+ previous), Shell (`kubectl exec`), rich overview, related Events |
| **Deployments** | Scale, Restart, Rollout history + undo, Pause/Resume; related Pods; **Show Pods**; related Events; **Delete with Options…** |
| **StatefulSets** | Scale, Restart, Rollout history + undo; related Pods; **Show Pods**; related Events; **Delete with Options…** |
| **DaemonSets** | Restart, Rollout history + undo; related Pods; **Show Pods**; related Events; **Delete with Options…** |
| **ReplicaSets** | Scale; related Pods; **Show Pods**; **Delete with Options…** |
| **Jobs** | Suspend/Resume, Cancel, Logs (via owned pods), related Events; **Delete with Options…** |
| **CronJobs** | Suspend/Resume, **Trigger Now**; related Events; **Delete with Options…** |

Universal for all: list + live watch, get, YAML view/edit/apply, delete, **force delete** (`gracePeriodSeconds=0`), JSON tree, labels/annotations view.

**Delete API options (backend):** optional `gracePeriodSeconds` and `propagationPolicy` on `DELETE`. UI: **Delete** (K8s default), **Delete with Options…** (controllers), **Force Delete…** (grace 0; does not strip finalizers).

---

## Networking

*(unchanged — see repo main for latest networking backlog)*

**Explicitly unimplemented (shared with workloads):** API-backed exec/shell into pods (local `kubectl exec` today).
