import SwiftUI

/// Related Events panel shared by Pods and workload detail overviews.
struct RelatedEventsSection: View {
    let events: [ResourceDetailModel.RelatedEvent]
    var isLoading = false

    var body: some View {
        DetailSection(title: "Events") {
            if isLoading {
                PodEventsSkeleton()
            } else if events.isEmpty {
                Text("No events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { RelatedEventRowView(event: $0) }
                }
            }
        }
    }
}
