import SwiftUI

struct SidebarView: View {
    @Bindable var app: AppModel

    var body: some View {
        List(selection: $app.selectedDestination) {
            Section("General") {
                Label("Overview", systemImage: "square.grid.2x2")
                    .tag(SidebarDestination.overview)
                HStack {
                    Label("Port Forwards", systemImage: "arrow.left.arrow.right")
                    Spacer(minLength: 8)
                    if app.portForwards.activeCount >= 1 {
                        Text("\(app.portForwards.activeCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(SidebarDestination.portForwards)
            }

            ForEach(ResourceSection.allCases, id: \.self) { section in
                let items = ResourceType.all.filter { $0.section == section }
                if !items.isEmpty {
                    Section(section.rawValue) {
                        ForEach(items) { resource in
                            HStack {
                                Label(resource.title, systemImage: resource.symbol)
                                Spacer(minLength: 8)
                                if let count = app.sidebarCounts.counts[resource.resource], count >= 1 {
                                    Text("\(count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
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
}
