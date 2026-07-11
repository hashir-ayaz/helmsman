import SwiftUI

/// Lens-style overview for Kubernetes Events: metadata rows + full Message well.
struct EventOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let type = nonEmpty(object["type"]?.stringValue) {
                    DetailRow(
                        label: "Type",
                        value: type,
                        valueColor: typeColor(type)
                    )
                }
                if let reason = nonEmpty(object["reason"]?.stringValue) {
                    DetailRow(
                        label: "Reason",
                        value: reason,
                        valueColor: ResourceColors.eventReasonColor(reason)
                    )
                }
                if let kind = nonEmpty(object["involvedObject"]?["kind"]?.stringValue) {
                    DetailRow(label: "Kind", value: kind)
                }
                if let name = nonEmpty(object["involvedObject"]?["name"]?.stringValue) {
                    DetailRow(label: "Name", value: name)
                }
                if let ns = nonEmpty(object["involvedObject"]?["namespace"]?.stringValue) {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let count = countValue {
                    DetailRow(label: "Count", value: count)
                }
                if let source = K8s.eventSourceLabel(object) {
                    DetailRow(label: "Source", value: source)
                }
                if let first = K8s.eventFirstSeen(object) {
                    DetailRow(label: "First Seen", value: first)
                }
                if let last = K8s.eventLastSeen(object) {
                    DetailRow(label: "Last Seen", value: last)
                }
            }
        }

        if let message = nonEmpty(object["message"]?.stringValue) {
            DetailSection(title: "Message") {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    private var countValue: String? {
        if let n = object["count"]?.intValue {
            return String(n)
        }
        return nonEmpty(object["count"]?.displayString)
    }

    private func typeColor(_ type: String) -> Color {
        type.lowercased() == "warning"
            ? ResourceColors.statusColor("Failed")
            : ResourceColors.statusColor("Running")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
