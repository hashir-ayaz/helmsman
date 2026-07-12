import Foundation

/// Active filter when navigating from a workload to the Pods list.
struct PodsListFilter: Equatable, Sendable {
    /// Kubernetes labelSelector string, e.g. `app=frontend`.
    let labelSelector: String
    /// Human label for the chip, e.g. `Deployment/frontend`.
    let sourceTitle: String
    /// Namespace pinned for the filtered list API calls.
    let namespace: String
}
