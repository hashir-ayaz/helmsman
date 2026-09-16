import SwiftUI

struct SidebarView: View {
    @Bindable var app: AppModel

    var body: some View {
        List(selection: $app.selectedDestination) {
            Section("General") {
                sidebarLabel("Overview", systemImage: "square.grid.2x2")
                    .tag(SidebarDestination.overview)

                sidebarLabel("Port Forwards", systemImage: "arrow.left.arrow.right")
                    .badge(app.portForwards.activeCount >= 1 ? app.portForwards.activeCount : 0)
                    .tag(SidebarDestination.portForwards)
            }

            ForEach(ResourceSection.allCases, id: \.self) { section in
                let items = ResourceType.all.filter { $0.section == section }
                if !items.isEmpty {
                    Section(section.rawValue) {
                        ForEach(items) { resource in
                            sidebarLabel(resource.title, systemImage: resource.symbol)
                                .badge(sidebarBadge(for: resource.resource))
                                .tag(SidebarDestination.resource(resource))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(.accentColor)
        .frame(minWidth: 215)
        .task(id: app.selectedContext) {
            while !Task.isCancelled {
                await app.portForwards.refresh(ctx: app.selectedContext)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Title stays primary; icon follows System Settings → Appearance → Accent color.
    private func sidebarLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.monochrome)
        }
        .labelStyle(.titleAndIcon)
    }

    /// `0` hides the badge; avoids wrapping `Label` in an `HStack`, which
    /// breaks SF Symbol redraw during sidebar List cell recycling.
    private func sidebarBadge(for resource: String) -> Int {
        guard let count = app.sidebarCounts.counts[resource], count >= 1 else { return 0 }
        return count
    }
}
