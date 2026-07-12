# Workload & Networking Feature Priorities

Prioritized backlog for Helmsman, ranked by how often operators need each feature and how much they would otherwise fall back to kubectl / Lens / k9s.

**Scope today:**
- **Workloads** — Pods, Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs
- **Networking** — Services, Ingresses, NetworkPolicies, Endpoints (+ modern gaps like EndpointSlices)

**Recommended next sprint (highest ROI):** workload P1 item 7 (API-backed exec). P1 #5, #6, and #8 are shipped.

**Architectural bets to schedule separately:** API-backed exec (streaming complexity).

---

## Workloads

### P0 — Weekly pain

*All items shipped — see **Shipped detail** and **Current baseline** below.*

| # | Feature | Status |
|---|---------|--------|
| 1 | **Owner → Pods navigation** | Shipped — detail drill-down + k9s-style **Show Pods** list navigation |
| 2 | **CronJob “Trigger now”** | Shipped — `POST .../cronjobs/{name}/trigger`; context menu **Trigger Now…** |
| 3 | **Force delete** | Shipped — `DELETE` with `gracePeriodSeconds=0`; context menu **Force Delete…** (all deletable resources) |
| 4 | **Related events on all workloads** | Shipped — shared Events panel on Pods + Deployments / STS / DS / Jobs / CronJobs detail |

#### Shipped detail (P0)

| # | Feature | Implementation |
|---|---------|----------------|
| 1 | **Owner → Pods navigation** | **(A) Detail drill-down:** On Deployments / STS / DS / RS inspect, `WorkloadOverview` loads related pods via server-side `labelSelector` (`spec.selector.matchLabels`). Click a pod row to replace the detail panel with that pod’s overview (`DetailFocus`, `RelatedPodsModel`, `RelatedPodRow`); **←** back returns to the workload. **(B) List navigation (k9s-style):** Context menu **Show Pods** on the same workload types fetches the object, builds the selector, pins namespace, and navigates to the Pods sidebar list with a filtered table + dismissible chip (`PodsListFilter`, `PodsListFilterBar`, `AppModel.showPods`). Watch SSE passes `labelSelector` so filtered pod lists reload without watching the entire namespace. |
| 2 | **CronJob “Trigger now”** | Backend `POST .../cronjobs/{name}/trigger` creates a one-off Job from the CronJob template. Frontend: **Trigger Now…** in CronJob context menu (`ResourceActionsModel`, `KubeAPIClient.triggerCronJob`). |
| 3 | **Force delete** | Backend `DELETE` accepts optional `gracePeriodSeconds` and `propagationPolicy` query params. Frontend: **Force Delete…** in context menu sets `gracePeriodSeconds=0` (`ResourceActionsModel.performForceDelete`). Does not strip finalizers. |
| 4 | **Related events on all workloads** | Shared `RelatedEventsSection` + `RelatedEventRowView` in `ResourceOverview` (after kind overview, before labels). Loaded via existing `GET .../events?fieldSelector=involvedObject.name=...,involvedObject.kind=...` (`ResourceDetailModel.loadEvents`, `supportsRelatedEvents` / `eventInvolvedObjectKind` in `ResourceCatalog`). Backend sorts events newest-first by Last Seen. Direct object events only — not aggregated child Pod/ReplicaSet events. |

### P1 — Core ops parity (next tier)

| # | Feature | Status |
|---|---------|--------|
| 5 | **Port-forward** | Shipped — Pods + Services; API sidecar sessions + **Port Forwards** sidebar page |
| 6 | **Real StatefulSet / DaemonSet rollout history** | Shipped — ControllerRevisions + undo |
| 7 | **API-backed pod exec** (or reliable bundled kubectl path) | Open |
| 8 | **Cascade delete options** | Shipped — Delete with Options sheet |

#### Shipped detail (P1)

| # | Feature | Implementation |
|---|---------|----------------|
| 5 | **Port-forward** | Backend: `client-go/tools/portforward` in the Go sidecar binds `127.0.0.1:<localPort>`; session manager with stats (connections, bytes sent/received). Routes: `POST .../pods|services/{name}/portforward`, `GET .../portforwards`, `POST .../portforwards/{id}/stop`, `DELETE .../portforwards/{id}`. Service forwards resolve a ready pod via Endpoints / EndpointSlices. Frontend: context menu **Port Forward** submenu (per container/service port) → **Port Forward** sheet (`localhost:` port + open-in-browser) → **Port Forwards** sidebar page with live table, stop/remove, open/copy URL. |
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
| **Pods** | Logs (+ previous), Shell (`kubectl exec`), **Port Forward**, rich overview, related Events |
| **Deployments** | Scale, Restart, Rollout history + undo, Pause/Resume; related Pods + drill-down; **Show Pods**; related Events; **Delete with Options…** |
| **StatefulSets** | Scale, Restart, Rollout history + undo; related Pods + drill-down; **Show Pods**; related Events; **Delete with Options…** |
| **DaemonSets** | Restart, Rollout history + undo; related Pods + drill-down; **Show Pods**; related Events; **Delete with Options…** |
| **ReplicaSets** | Scale; related Pods + drill-down; **Show Pods**; **Delete with Options…** |
| **Jobs** | Suspend/Resume, Cancel, Logs (via owned pods), related Events; **Delete with Options…** |
| **CronJobs** | Suspend/Resume, **Trigger Now**; related Events; **Delete with Options…** |

**Cross-cutting detail UX (workloads):**
- **Related pods (detail):** `WorkloadOverview` → clickable pod rows → in-place pod detail (`DetailFocus`).
- **Show Pods (list):** context menu → filtered Pods list + dismissible `Pods for Deployment/name` bar (`PodsListFilter`).
- **Related events:** `RelatedEventsSection` on inspect when `supportsRelatedEvents` is set.
- **Port forwards:** sidebar **Port Forwards** page lists active/stopped sessions; badge shows active count.

Universal for all: list + live watch, get, YAML view/edit/apply, delete, **force delete** (`gracePeriodSeconds=0`), JSON tree, labels/annotations view.

**Delete API options (backend):** optional `gracePeriodSeconds` and `propagationPolicy` on `DELETE`. UI: **Delete** (K8s default), **Delete with Options…** (controllers), **Force Delete…** (grace 0; does not strip finalizers).

**Watch API (backend):** `labelSelector` / `fieldSelector` query params on resource watch SSE (used by filtered Pods list).

---

## Networking

Today Networking is **mostly generic CRUD + watch + YAML**, with light overview polish for Services and Endpoints. Ingresses and NetworkPolicies fall back to `GenericOverview`. No networking-specific backend actions exist (everything goes through the dynamic resource pipeline).

**Recommended networking sprint (after or interleaved with workload P0):** N2 → N3. N1 is shipped.

### P0 — Weekly pain (do these first)

| # | Feature | Status |
|---|---------|--------|
| N1 | **Relationship navigation** | Shipped — Service → Pods / Endpoints; Ingress → Services → Pods |
| N2 | **EndpointSlices in catalog** | Open — N1 includes EndpointSlice fallback on Service detail only |
| N3 | **Service backend health cues** | Open — partial: ready/not-ready counts on Service detail Endpoints section |

#### Shipped detail (networking P0)

| # | Feature | Implementation |
|---|---------|----------------|
| N1 | **Relationship navigation** | **Frontend-only** — reuses existing list/get APIs with server-side `labelSelector`. **Service detail:** `ServiceOverview` loads related pods (capped at 20 + **Show all in Pods list…**) via `RelatedPodsModel`; Endpoints section via `RelatedEndpointsModel` (Endpoints GET, EndpointSlice list fallback); drill to Endpoints detail or pod rows. **Endpoints detail:** clickable `targetRef` pod chips. **Ingress detail:** `IngressOverview` lists hosts/paths/backends; click backend → Service detail drill. **Show Pods** context menu extended to Services (`supportsShowPods`, `K8s.podMatchLabels`). **Drill stack:** generalized `DetailFocus` with `parentResource` + anchor for Ingress → Service → Pod back navigation. |

### P1 — Core ops parity (next tier)

| # | Feature | Status |
|---|---------|--------|
| N4 | **Port-forward to Services** | Shipped — same session manager as workload #5; Service context menu + Endpoints resolution |
| N5 | **Ingress custom overview** | Partial — N1 ships hosts/paths/backends + Service drill; TLS/class polish remains |
| N6 | **Open / copy networking affordances** | Copy Service DNS (`svc.ns.svc.cluster.local`); open LoadBalancer hostname/IP; open Ingress host URL. |
| N7 | **NetworkPolicy readable summary** | podSelector, policyTypes, ingress/egress peers & ports as structured overview — not only raw YAML. |

### P2 — Strong polish (after P0–P1)

| # | Feature | Why it matters |
|---|---------|----------------|
| N8 | **IngressClass in catalog** | Needed to understand which controller owns an Ingress. |
| N9 | **Gateway API resources** | Gateways, HTTPRoutes (and optionally GRPCRoute / TCPRoute / TLSRoute) — increasingly the Ingress successor. |
| N10 | **Service selector / port quick edit** | YAML apply works; dedicated edit is convenience for common ops. |

### P3 — Power-user / later

| # | Feature | Notes |
|---|---------|-------|
| N11 | CNI policy CRDs (e.g. CiliumNetworkPolicy) | Optional catalog entries for common CNIs. |
| N12 | Istio / service-mesh CRDs | VirtualService, DestinationRule, etc. — mesh-specific audiences. |
| N13 | NetworkPolicy traffic visualization | Nice-to-have after textual rule summaries exist. |

### Current baseline (already shipped)

| Resource | Specialized behavior |
|----------|----------------------|
| **Services** | Table + live watch; `ServiceOverview` (type, ClusterIP, ports, selectors, **related Pods**, **Endpoints** with EndpointSlice fallback); **Show Pods** context menu; pod/Endpoints drill-down; `PortChipsView`; **Port Forward** |
| **Ingresses** | `IngressOverview` (hosts, paths, backends, ingress class, LB address); drill to backend **Service** |
| **NetworkPolicies** | Generic list/get/YAML/delete only (`GenericOverview`) |
| **Endpoints** | Table + live watch; `EndpointsOverview` (ready/not-ready counts + address chips); clickable pod `targetRef` drill-down |

**Not in catalog yet:** EndpointSlices, IngressClasses, Gateway API, CNI/mesh CRDs.

**Explicitly unimplemented (shared with workloads):** API-backed exec/shell into pods (local `kubectl exec` today).
