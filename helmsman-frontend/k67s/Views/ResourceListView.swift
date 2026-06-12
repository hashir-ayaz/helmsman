import SwiftUI
import AppKit

/// Generic, Table-driven list reused for every resource type. Columns and rows
/// come entirely from the backend `TablePayload`.
struct ResourceListView: View {
    @Bindable var app: AppModel
    let resource: ResourceType

    @Environment(\.openWindow) private var openWindow
    @State private var model = ResourceListModel()
    @State private var actions = ResourceActionsModel()
    @State private var selectedRowID: TablePayload.Row.ID?

    private var isPods: Bool { resource.isPods }

    private var selectedRow: TablePayload.Row? {
        guard let id = selectedRowID else { return nil }
        return model.payload?.rows.first { $0.id == id }
    }

    /// Reload whenever context, namespace, or resource changes.
    private var taskKey: String {
        "\(app.selectedContext)|\(app.namespaceParam ?? "*")|\(resource.id)"
    }

    var body: some View {
        HSplitView {
            table
                .overlay { overlay }
            if let row = selectedRow {
                ResourceDetailView(app: app, resource: resource, row: row)
                    .id(row.id)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
            }
        }
        .navigationTitle(resource.title)
        .searchable(text: $model.searchText, prompt: "Search \(resource.title.lowercased())…")
        .toolbar { toolbarContent }
        .rowActionAlerts(actions)
        .task(id: taskKey) {
            actions.resource = resource
            actions.onMutated = { Task { await reload() } }
            selectedRowID = nil
            await reload()
        }
    }

    private var table: some View {
        Table(of: TablePayload.Row.self, selection: $selectedRowID) {
            TableColumnForEach(model.visibleColumns) { visible in
                TableColumn(visible.column.name) { row in
                    cell(row: row, column: visible.column, columnIndex: visible.id)
                }
            }
        } rows: {
            ForEach(model.rows) { row in
                TableRow(row)
            }
        }
        // Stable identity per resource/namespace/context so SwiftUI rebuilds the
        // table when the column set changes rather than mutating it mid-layout.
        .id(taskKey)
        .contextMenu(forSelectionType: TablePayload.Row.ID.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            selectedRowID = ids.first
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<TablePayload.Row.ID>) -> some View {
        if let id = ids.first, let row = model.payload?.rows.first(where: { $0.id == id }) {
            let hasNamespace = !(row.object.namespace ?? "").isEmpty
            let canEditSingleObject = hasNamespace || resource.scope == .cluster

            Button("Inspect") { selectedRowID = id }

            if isPods {
                Button("Logs") { openLogs(row: row, previous: false) }
                Button("Previous Logs") { openLogs(row: row, previous: true) }
            }

            if canEditSingleObject {
                Button("Edit YAML…") { openYAML(row: row) }
            }

            Divider()

            Button("Copy Name") { copyToPasteboard(row.object.name) }
            Button("Copy Namespace/Name") {
                copyToPasteboard("\(row.object.namespace ?? "")/\(row.object.name)")
            }

            if resource.supportsScale || resource.restartWorkload != nil {
                Divider()
                if resource.supportsScale {
                    Button("Scale…") { actions.beginScale(row, currentReplicas: currentReplicas(of: row)) }
                }
                if resource.restartWorkload != nil {
                    Button("Restart") { actions.restartTarget = row }
                }
            }

            if canEditSingleObject {
                Divider()
                Button("Delete", role: .destructive) { actions.deleteTarget = row }
            }
        }
    }

    private func openLogs(row: TablePayload.Row, previous: Bool) {
        openWindow(id: "logs", value: LogWindowTarget(
            ctx: app.selectedContext,
            namespace: row.object.namespace ?? "",
            pod: row.object.name,
            previous: previous
        ))
    }

    private func openYAML(row: TablePayload.Row) {
        openWindow(id: "yaml", value: YAMLWindowTarget(
            ctx: app.selectedContext,
            namespace: row.object.namespace ?? "",
            resource: resource.resource,
            name: row.object.name
        ))
    }

    /// Best-effort current replica count for the scale modal, parsed from a
    /// "Ready" column cell like "1/1" (uses the desired count after the slash).
    private func currentReplicas(of row: TablePayload.Row) -> String {
        guard let readyIndex = model.columns.firstIndex(where: { $0.name.lowercased() == "ready" }),
              let cell = row.cells[safe: readyIndex]?.displayString
        else { return "" }
        return cell.split(separator: "/").last.map(String.init) ?? cell
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    @ViewBuilder
    private func cell(row: TablePayload.Row, column: TablePayload.Column, columnIndex: Int) -> some View {
        let text = row.cells[safe: columnIndex]?.displayString ?? ""
        let columnName = column.name.lowercased()

        if columnIndex == model.visibleColumns.first?.id {
            HStack(spacing: 6) {
                if let status = model.leadingStatus(for: row) {
                    StatusDot(status: status)
                }
                Text(text).lineLimit(1)
            }
        } else if columnName == "status" || columnName == "phase" {
            Text(text)
                .foregroundStyle(ResourceColors.statusColor(text))
                .fontWeight(.medium)
        } else if columnName == "type" {
            Text(text)
                .foregroundStyle(.tint)
                .fontWeight(.medium)
        } else if columnName.hasPrefix("port") {
            PortChipsView(value: text)
        } else {
            Text(text).lineLimit(1)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.isLoading && model.payload == nil {
            ProgressView()
        } else if let error = model.error {
            ErrorStateView(error: error) {
                Task { await reload() }
            }
        } else if model.payload?.rows.isEmpty == true {
            ContentUnavailableView("No \(resource.title)", systemImage: resource.symbol)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: $model.showWide) {
                Label("Wide", systemImage: "arrow.left.and.right")
            }
            .help("Show all columns")

            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh")
        }
    }

    private func reload() async {
        await model.load(ctx: app.selectedContext, ns: app.namespaceParam, resource: resource)
    }
}
