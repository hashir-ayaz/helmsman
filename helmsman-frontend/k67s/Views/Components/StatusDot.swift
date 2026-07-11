import SwiftUI

struct StatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(ResourceColors.statusColor(status))
            .frame(width: 8, height: 8)
    }
}

enum ResourceColors {
    static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "active", "bound", "ready", "succeeded", "completed":
            return .green
        case "pending", "containercreating", "podscheduled", "initialized", "terminating":
            return .orange
        case "failed", "error", "crashloopbackoff", "oomkilled", "evicted", "imagepullbackoff":
            return .red
        case "unknown":
            return .gray
        default:
            return .secondary
        }
    }

    /// Event reasons that indicate a real problem (scheduling failures, mount errors, etc.).
    static func isCriticalEventReason(_ reason: String) -> Bool {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let lower = normalized.lowercased()
        if lower.hasPrefix("failed") { return true }

        switch lower {
        case "backoff", "unhealthy", "oomkilling", "evicted",
             "evictionthresholdmet", "networknotready", "errimageneverpull":
            return true
        default:
            return false
        }
    }

    static func eventReasonColor(_ reason: String) -> Color {
        isCriticalEventReason(reason) ? .red : .primary
    }
}
