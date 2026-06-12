import Foundation

/// A kubeconfig context as returned by `GET /api/v1/contexts`.
struct ContextInfo: Decodable, Identifiable, Sendable, Hashable {
    let name: String
    let cluster: String
    let namespace: String
    let isCurrent: Bool

    var id: String { name }
}
