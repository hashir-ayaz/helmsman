import SwiftUI

/// Generic detail panel for one selected row: Overview (selected fields), the
/// full raw object as a JSON tree, and the YAML representation.
struct ResourceDetailView: View {
    @Bindable var app: AppModel
    let resource: ResourceType
    let row: TablePayload.Row

    @State private var model = ResourceDetailModel()
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case object = "Object"
        case yaml = "YAML"
    }

    /// Detail requests use the row's own namespace (rows may span namespaces).
    private var namespace: String? {
        resource.scope == .cluster ? nil : row.object.namespace
    }

    /// Status string for the header dot: Event type, else pod/object phase.
    private var headerStatus: String? {
        if model.object?["kind"]?.stringValue == "Event",
           let type = model.object?["type"]?.stringValue,
           !type.isEmpty {
            return type.lowercased() == "warning" ? "Failed" : "Running"
        }
        return model.object?["status"]?["phase"]?.stringValue
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            async let objectLoad: Void = model.loadObject(
                ctx: app.selectedContext, ns: namespace,
                resource: resource, name: row.object.name
            )
            async let eventsLoad: Void = resource.isPods
                ? model.loadEvents(
                    ctx: app.selectedContext,
                    ns: namespace,
                    podName: row.object.name
                )
                : ()
            _ = await (objectLoad, eventsLoad)
        }
        .onChange(of: tab) { _, newTab in
            guard newTab == .yaml else { return }
            Task {
                await model.loadYAML(
                    ctx: app.selectedContext, ns: namespace,
                    resource: resource, name: row.object.name
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let status = headerStatus {
                    StatusDot(status: status)
                }
                Text(row.object.name)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if let namespace = row.object.namespace {
                Label(namespace, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: overviewTab
        case .object: objectTab
        case .yaml: yamlTab
        }
    }

    private var overviewTab: some View {
        ScrollView {
            Group {
                if model.isLoadingObject {
                    DetailOverviewSkeleton()
                } else if let object = model.object {
                    ResourceOverview(
                        object: object,
                        podEvents: model.events,
                        isLoadingPodEvents: model.isLoadingEvents
                    )
                } else if let error = model.error {
                    Text(error.errorDescription ?? "Error")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    DetailOverviewSkeleton()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentAppear()
        }
    }

    private var objectTab: some View {
        ScrollView {
            if let object = model.object {
                JSONTreeView(key: nil, value: object)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentAppear()
            } else if model.isLoadingObject {
                DetailObjectSkeleton()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                DetailObjectSkeleton()
                    .padding(12)
            }
        }
    }

    private var yamlTab: some View {
        ScrollView([.vertical, .horizontal]) {
            if model.isLoadingYAML {
                DetailYAMLSkeleton()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if let yaml = model.yaml {
                Text(yaml)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentAppear()
            } else if let error = model.error {
                Text(error.errorDescription ?? "Error")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

}
