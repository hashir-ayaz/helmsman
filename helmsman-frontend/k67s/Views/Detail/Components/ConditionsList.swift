import SwiftUI

/// Renders status.conditions[] with colored True/False indicators.
/// Shared by Pod / Deployment / Node / Job overviews.
struct ConditionsList: View {
    let conditions: [JSONValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                let type = condition["type"]?.stringValue ?? "—"
                let status = condition["status"]?.stringValue ?? "Unknown"
                HStack(spacing: 6) {
                    Image(systemName: icon(for: status))
                        .foregroundStyle(color(for: status))
                        .font(.caption)
                    Text(type).font(.callout)
                    Spacer(minLength: 0)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
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
