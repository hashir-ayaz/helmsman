import Foundation

/// Identifies which pod's logs a separate window shows. `Codable & Hashable`
/// because SwiftUI's `WindowGroup(for:)` carries it as the window's value.
struct LogWindowTarget: Codable, Hashable, Identifiable {
    let ctx: String
    let namespace: String
    let pod: String
    let previous: Bool

    var id: String { "\(ctx)/\(namespace)/\(pod)/\(previous)" }

    var windowTitle: String {
        previous ? "\(pod) — Previous Logs" : "\(pod) — Logs"
    }
}
