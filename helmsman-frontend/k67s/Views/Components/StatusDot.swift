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
}
