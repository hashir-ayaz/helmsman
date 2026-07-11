import SwiftUI

/// Renders status.conditions[] with colored True/False indicators.
/// Shared by Pod / Deployment / Node / Job overviews.
struct ConditionsList: View {
    let conditions: [JSONValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conditions, id: \.self) { condition in
                conditionRow(condition)
            }
        }
    }

    @ViewBuilder
    private func conditionRow(_ condition: JSONValue) -> some View {
        let type = condition["type"]?.stringValue ?? "—"
        let status = condition["status"]?.stringValue ?? "Unknown"
        let reason = condition["reason"]?.stringValue
        let message = condition["message"]?.stringValue

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: status))
                    .foregroundStyle(color(for: status))
                    .font(.caption)
                Text(type).font(.callout)
                Spacer(minLength: 0)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(color(for: status))
            }

            if status != "True" {
                VStack(alignment: .leading, spacing: 2) {
                    if let reason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "True": "checkmark.circle.fill"
        case "False": "xmark.circle.fill"
        default: "questionmark.circle.fill"
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "True": .green
        case "False": .red
        default: .secondary
        }
    }
}
