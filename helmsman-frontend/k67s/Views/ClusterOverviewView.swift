import SwiftUI

/// Cluster-wide dashboard: summary counts, workload health bars, warning events,
/// and node status. Data is aggregated client-side from generic list APIs.
struct ClusterOverviewView: View {
    @Bindable var app: AppModel
    @State private var model = ClusterOverviewModel()

    private var taskKey: String { app.selectedContext }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCards
                workloadBars
                bottomPanels
            }
            .padding(16)
        }
        .contentAppear()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Cluster Overview")
        .scopePickerToolbar(app: app)
        .toolbar { toolbarContent }
        .overlay {
            if model.isLoading && model.summaryCards.isEmpty {
                ClusterOverviewSkeleton()
            }
        }
        .task(id: taskKey) {
            model.reset()
            await model.load(ctx: app.selectedContext)
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            ForEach(model.summaryCards) { card in
                Button {
                    app.selectResource(card.resource)
                } label: {
                    SummaryCardView(card: card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Workload bars

    private var workloadBars: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resource Status")
                .font(.headline)

            ForEach(model.workloadBars) { bar in
                WorkloadBarView(bar: bar) {
                    app.selectResource(bar.resource)
                }
            }
        }
    }

    // MARK: - Bottom panels

    private var bottomPanels: some View {
        HSplitView {
            warningEventsPanel
                .frame(minWidth: 280)
            nodesPanel
                .frame(minWidth: 320)
        }
        .frame(minHeight: 280)
    }

    private var warningEventsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Warning Events")
                    .font(.headline)
                if !model.warningEvents.isEmpty {
                    Text("\(model.warningEvents.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
            }

            if let error = model.warningsError {
                inlineError(error)
            } else if model.warningEvents.isEmpty && !model.isLoading {
                Text("No warning events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                List(model.warningEvents) { event in
                    WarningEventRowView(event: event)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var nodesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nodes")
                    .font(.headline)
                if !model.nodes.isEmpty {
                    Text("\(model.nodes.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button("View All") {
                    if let nodes = ResourceType.all.first(where: { $0.resource == "nodes" }) {
                        app.selectResource(nodes)
                    }
                }
                .font(.caption)
            }

            if let error = model.nodesError {
                inlineError(error)
            } else if model.nodes.isEmpty && !model.isLoading {
                Text("No nodes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Table(model.nodes) {
                    TableColumn("Name") { node in
                        Text(node.name).lineLimit(1)
                    }
                    TableColumn("Status") { node in
                        HStack(spacing: 6) {
                            StatusDot(status: node.status)
                            Text(node.status)
                        }
                    }
                    TableColumn("Roles") { node in
                        Text(node.roles).lineLimit(1)
                    }
                    TableColumn("Age") { node in
                        Text(node.age).lineLimit(1)
                    }
                    TableColumn("Version") { node in
                        Text(node.version).lineLimit(1)
                    }
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await model.load(ctx: app.selectedContext) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh")
        }
    }
}

// MARK: - Subviews

private struct SummaryCardView: View {
    let card: ClusterOverviewModel.SummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: card.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Spacer()
            }
            if let count = card.count {
                Text("\(count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(card.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = card.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct WorkloadBarView: View {
    let bar: ClusterOverviewModel.WorkloadBar
    let onTitleTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTitleTap) {
                Text(bar.title)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)

            if let error = bar.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if bar.total == 0 {
                Text("No resources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: bar.healthyFraction)
                    .tint(.green)

                Text(bar.buckets.map { "\($0.count) \($0.label)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct WarningEventRowView: View {
    let event: ClusterOverviewModel.WarningEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: ResourceColors.isCriticalEventReason(event.reason) ? "Failed" : "Normal")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.reason)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResourceColors.eventReasonColor(event.reason))
                    Spacer(minLength: 8)
                    if !event.age.isEmpty {
                        Text(event.age)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !event.object.isEmpty {
                    Text(event.object)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !event.message.isEmpty {
                    Text(event.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
