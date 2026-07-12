import Foundation

/// One entry in a workload's rollout history (ReplicaSet for Deployments,
/// ControllerRevision for StatefulSets and DaemonSets).
/// Returned by `GET .../rollout/history`.
struct RevisionEntry: Decodable, Identifiable, Sendable {
    let revision: Int64
    let name: String
    let createdAt: String
    let images: [String]
    let replicas: Int64
    let changeCause: String?

    var id: Int64 { revision }
}
