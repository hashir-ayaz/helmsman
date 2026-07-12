import SwiftUI

/// A single related event row in a resource detail panel.
struct RelatedEventRowView: View {
    let event: ResourceDetailModel.RelatedEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: ResourceColors.isCriticalEventReason(event.reason) ? "Failed" : "Normal")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.reason)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResourceColors.eventReasonColor(event.reason))
                    if !event.type.isEmpty {
                        Text(event.type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if !event.age.isEmpty {
                        Text(event.age)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !event.message.isEmpty {
                    Text(event.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
