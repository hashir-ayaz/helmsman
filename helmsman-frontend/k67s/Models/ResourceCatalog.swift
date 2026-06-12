import Foundation

/// A Kubernetes resource type shown in the sidebar. `resource` is the API path
/// segment — a bare kind (`pods`) for core/v1 types, or `kind.group`
/// (`deployments.apps`) to disambiguate grouped types and CRDs.
struct ResourceType: Identifiable, Hashable, Sendable {
    let title: String
    let resource: String
    let symbol: String
    let scope: Scope
    let section: ResourceSection

    var id: String { resource }

    enum Scope: Sendable {
        case namespaced
        case cluster
    }

    // MARK: - Mutation capabilities

    /// Only pods expose the log endpoint.
    var isPods: Bool { resource == "pods" }

    /// The backend scale endpoint is hardcoded to deployments.
    var supportsScale: Bool { resource == "deployments.apps" }

    /// The `{workload}` path segment for rollout restart, or `nil` if not restartable.
    var restartWorkload: String? {
        switch resource {
        case "deployments.apps": "deployments"
        case "statefulsets.apps": "statefulsets"
        case "daemonsets.apps": "daemonsets"
        default: nil
        }
    }
}

enum ResourceSection: String, CaseIterable, Hashable, Sendable {
    case workloads = "Workloads"
    case networking = "Networking"
    case config = "Config"
    case storage = "Storage"
    case cluster = "Cluster"
}

extension ResourceType {
    /// Curated catalog rendered through the generic list view.
    static let all: [ResourceType] = [
        // Workloads
        .init(title: "Pods", resource: "pods", symbol: "shippingbox", scope: .namespaced, section: .workloads),
        .init(title: "Deployments", resource: "deployments.apps", symbol: "square.stack.3d.up", scope: .namespaced, section: .workloads),
        .init(title: "StatefulSets", resource: "statefulsets.apps", symbol: "square.stack.3d.up.fill", scope: .namespaced, section: .workloads),
        .init(title: "DaemonSets", resource: "daemonsets.apps", symbol: "square.grid.3x3", scope: .namespaced, section: .workloads),
        .init(title: "ReplicaSets", resource: "replicasets.apps", symbol: "square.on.square", scope: .namespaced, section: .workloads),
        .init(title: "Jobs", resource: "jobs.batch", symbol: "hammer", scope: .namespaced, section: .workloads),
        .init(title: "CronJobs", resource: "cronjobs.batch", symbol: "clock.arrow.circlepath", scope: .namespaced, section: .workloads),

        // Networking
        .init(title: "Services", resource: "services", symbol: "network", scope: .namespaced, section: .networking),
        .init(title: "Ingresses", resource: "ingresses.networking.k8s.io", symbol: "arrow.triangle.branch", scope: .namespaced, section: .networking),
        .init(title: "NetworkPolicies", resource: "networkpolicies.networking.k8s.io", symbol: "shield.lefthalf.filled", scope: .namespaced, section: .networking),
        .init(title: "Endpoints", resource: "endpoints", symbol: "point.3.connected.trianglepath.dotted", scope: .namespaced, section: .networking),

        // Config
        .init(title: "ConfigMaps", resource: "configmaps", symbol: "doc.text", scope: .namespaced, section: .config),
        .init(title: "Secrets", resource: "secrets", symbol: "lock.doc", scope: .namespaced, section: .config),

        // Storage
        .init(title: "PersistentVolumes", resource: "persistentvolumes", symbol: "externaldrive", scope: .cluster, section: .storage),
        .init(title: "PVCs", resource: "persistentvolumeclaims", symbol: "externaldrive.badge.plus", scope: .namespaced, section: .storage),
        .init(title: "StorageClasses", resource: "storageclasses.storage.k8s.io", symbol: "square.stack", scope: .cluster, section: .storage),

        // Cluster
        .init(title: "Namespaces", resource: "namespaces", symbol: "folder", scope: .cluster, section: .cluster),
        .init(title: "Nodes", resource: "nodes", symbol: "cpu", scope: .cluster, section: .cluster),
        .init(title: "Events", resource: "events", symbol: "bell", scope: .namespaced, section: .cluster),
    ]
}
