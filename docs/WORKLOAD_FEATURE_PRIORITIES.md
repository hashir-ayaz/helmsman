# Workload & Networking Feature Priorities

Prioritized backlog for Helmsman, ranked by how often operators need each feature and how much they would otherwise fall back to kubectl / Lens / k9s.

**Scope today:**
- **Workloads** — Pods, Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs
- **Networking** — Services, Ingresses, NetworkPolicies, Endpoints (+ modern gaps like EndpointSlices)

**Recommended next sprint (highest ROI):** workload items 1 → 2 → 3 → 4 under P0. Relatively contained vs streaming work, and they remove the most common “open Terminal” moments.

**Architectural bets to schedule separately:** port-forward and API-backed exec (streaming complexity).

---

## Workloads

### P0 — Weekly pain (do these first)

| # | Feature | Why it matters |
|---|---------|----------------|
| 1 | **Owner → Pods navigation** | From a Deployment / StatefulSet / DaemonSet / Job / CronJob: “Show pods” (label/owner filter). Core mental model of Kubernetes; unlocks logs/shell without hunting. |
| 2 | **CronJob “Trigger now”** | Create a Job from the CronJob template. Extremely common (“test this schedule”); currently impossible in-app. |
| 3 | **Force delete** | Delete with `gracePeriodSeconds=0` (and optionally `propagationPolicy`). Unblocks stuck `Terminating` pods/resources. |
| 4 | **Related events on all workloads** | Same event panel Pods already have, for Deployments / STS / DS / Jobs / CronJobs. Needed for CrashLoop, failed rollouts, scheduling issues. |

### P1 — Core ops parity (next tier)

| # | Feature | Why it matters |
|---|---------|----------------|
| 5 | **Port-forward** | Pod (and ideally Service). Biggest Lens/k9s differentiator for local debugging; needs bidirectional streaming. |
| 6 | **Real StatefulSet / DaemonSet rollout history** | ControllerRevisions + undo. UI already promises this; backend is Deployment/ReplicaSet-only today. |
| 7 | **API-backed pod exec** (or reliable bundled kubectl path) | Shell without depending on host `kubectl`/PATH. Matters for the packaged DMG. |
| 8 | **Cascade delete options** | Foreground / background / orphan when deleting Deployments etc., so teardown doesn’t leave orphans by surprise. |

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
| **Pods** | Logs (+ previous), Shell (`kubectl exec`), rich overview, pod events |
| **Deployments** | Scale, Restart, Rollout history + undo, Pause/Resume |
| **StatefulSets** | Scale, Restart *(rollout history menu exists; backend Deployment-only)* |
| **DaemonSets** | Restart *(same rollout-history caveat)* |
| **ReplicaSets** | Scale |
| **Jobs** | Suspend/Resume, Cancel, Logs (via owned pods) |
| **CronJobs** | Suspend/Resume |

Universal for all: list + live watch, get, YAML view/edit/apply, delete, JSON tree, labels/annotations view.

---

## Networking

Today Networking is **mostly generic CRUD + watch + YAML**, with light overview polish for Services and Endpoints. Ingresses and NetworkPolicies fall back to `GenericOverview`. No networking-specific backend actions exist (everything goes through the dynamic resource pipeline).

**Recommended networking sprint (after or interleaved with workload P0):** N1 → N2 → N3. These close the “why isn’t traffic reaching my app?” loop without streaming complexity. Port-forward (shared with workload #5) remains the big architectural bet.

### P0 — Weekly pain (do these first)

| # | Feature | Why it matters |
|---|---------|----------------|
| N1 | **Relationship navigation** | Service → matching Pods / Endpoints(/Slices); Ingress → backend Service(s) → Pods. Core debugging mental model; without it users leave for kubectl. |
| N2 | **EndpointSlices in catalog** | Modern clusters use EndpointSlices; legacy Endpoints alone is incomplete for backend diagnosis. |
| N3 | **Service backend health cues** | Empty endpoints, selector mismatch warnings, ready vs not-ready summary linked from the Service. Answers “is anything behind this Service?” |

### P1 — Core ops parity (next tier)

| # | Feature | Why it matters |
|---|---------|----------------|
| N4 | **Port-forward to Services** | Same streaming work as workload #5; Service target is equally common for local debugging. |
| N5 | **Ingress custom overview** | Hosts, paths, TLS, backends, ingress class, loadBalancer status — today YAML/JSON only. |
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
| **Services** | Table + live watch; `ServiceOverview` (type, ClusterIP, ports, selectors); `PortChipsView` for Port(s) columns |
| **Ingresses** | Generic list/get/YAML/delete only (`GenericOverview`) |
| **NetworkPolicies** | Generic list/get/YAML/delete only (`GenericOverview`) |
| **Endpoints** | Table + live watch; `EndpointsOverview` (ready/not-ready counts + address chips) |

**Not in catalog yet:** EndpointSlices, IngressClasses, Gateway API, CNI/mesh CRDs.

**Explicitly unimplemented (shared with workloads):** port-forward (bidirectional streaming), exec/shell into pods.
