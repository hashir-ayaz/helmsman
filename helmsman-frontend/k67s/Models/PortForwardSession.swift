import Foundation

/// A server-managed port-forward session returned by the API.
struct PortForwardSession: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let context: String
    let kind: String
    let resource: String
    let namespace: String
    let pod: String
    let localPort: Int
    let remotePort: Int
    let container: String?
    let status: String
    let connections: Int
    let bytesSent: Int64
    let bytesReceived: Int64
    let error: String?
    let startedAt: String

    var isActive: Bool { status == "active" }

    var portsDescription: String {
        "localhost:\(localPort) -> :\(remotePort)"
    }

    var browserURL: URL? {
        URL(string: "http://localhost:\(localPort)")
    }
}

enum PortForwardByteFormatter {
    static func format(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f KB", value / 1_000)
        }
        return "\(bytes) B"
    }
}
