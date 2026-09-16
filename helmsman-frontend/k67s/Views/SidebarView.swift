import SwiftUI

struct SidebarView: View {
    @Bindable var app: AppModel

    var body: some View {
        List(selection: $app.selectedDestination) {
            Section("General") {
                Label("Overview", systemImage: "square.grid.2x2")
                    .labelStyle(.titleAndIcon)
                    .tag(SidebarDestination.overview)

                Label("Port Forwards", systemImage: "arrow.left.arrow.right")
                    .labelStyle(.titleAndIcon)
                    .badge(app.portForwards.activeCount >= 1 ? app.portForwards.activeCount : 0)
                    .tag(SidebarDestination.portForwards)
            }

            ForEach(ResourceSection.allCases, id: \.self) { section in
                let items = ResourceType.all.filter { $0.section == section }
                if !items.isEmpty {
                    Section(section.rawValue) {
                        ForEach(items) { resource in
                            Label(resource.title, systemImage: resource.symbol)
                                .labelStyle(.titleAndIcon)
                                .badge(sidebarBadge(for: resource.resource))
                                .tag(SidebarDestination.resource(resource))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 215)
        .task(id: app.selectedContext) {
            while !Task.isCancelled {
                await app.portForwards.refresh(ctx: app.selectedContext)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// `0` hides the badge; avoids wrapping `Label` in an `HStack`, which
    /// breaks SF Symbol redraw during sidebar List cell recycling.
    private func sidebarBadge(for resource: String) -> Int {
        guard let count = app.sidebarCounts.counts[resource], count >= 1 else { return 0 }
        return count
    }
}
