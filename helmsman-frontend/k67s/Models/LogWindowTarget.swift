import Foundation

/// Identifies which pod's logs a separate window shows. `Codable & Hashable`
/// because SwiftUI's `WindowGroup(for:)` carries it as the window's value.
struct LogWindowTarget: Codable, Hashable, Identifiable {
    let ctx: String
    let namespace: String
    /// Set when opened from a Pod row; nil when opened from a Job (resolved on open).
    let pod: String?
    /// Set when opened from a Job row; pods are listed via `job-name` label.
    let job: String?
    let previous: Bool

    var id: String {
        if let job {
            return "\(ctx)/\(namespace)/job/\(job)/\(previous)"
        }
        return "\(ctx)/\(namespace)/pod/\(pod ?? "")/\(previous)"
    }

    var windowTitle: String {
        if let job {
            return previous ? "\(job) — Previous Job Logs" : "\(job) — Job Logs"
        }
        let podName = pod ?? ""
        return previous ? "\(podName) — Previous Logs" : "\(podName) — Logs"
    }
}
