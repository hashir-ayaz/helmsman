import Foundation

/// Readiness reported by `GET /api/v1/status`.
struct ClusterStatus: Decodable, Equatable {
    let ready: Bool
    let code: String
    let message: String
}
