import Foundation

/// Readiness reported by `GET /api/v1/contexts/{ctx}/status`.
struct ClusterStatus: Decodable, Equatable, Sendable {
    let ready: Bool
    let code: String
    let message: String
}

extension ClusterStatus {
    /// The typed error for a not-ready probe, or nil when the cluster is reachable.
    var failure: APIError? {
        ready ? nil : .unavailable(code: code, message: message)
    }
}
