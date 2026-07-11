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
    private var isEvents: Bool { resource.resource == "events" }

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
            model.willReload = { selectedRowID = nil }
            actions.onMutated = {
                // Clear stale selection and cancel any pending watch-triggered
                // reload before issuing the authoritative post-mutation reload.
                // Without this, the watch DELETED event fires a second load()
                // ~300 ms later; if that second load fails, payload becomes nil
                // while selectedRowID still references the deleted row, causing
                // an NSTableView assertion crash (invalid selection index).
                selectedRowID = nil
                model.cancelPendingReload()
                Task { await reload() }
            }
            selectedRowID = nil
            await reload()
            await model.watch(ctx: app.selectedContext, ns: app.namespaceParam, resource: resource)
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
        .onChange(of: model.visibleColumns.map(\.id)) { _, _ in
            // Column structure changed — NSTableView cannot keep a valid selection index.
            selectedRowID = nil
        }
        .onChange(of: model.rows.map(\.id)) { _, ids in
            if let selected = selectedRowID, !ids.contains(selected) {
                selectedRowID = nil
            }
        }
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

            // ── Inspect / Logs ──────────────────────────────────────────────
            Button("Inspect") { selectedRowID = id }

            if isPods {
                Button("Logs") { openLogs(row: row, previous: false) }
                Button("Previous Logs") { openLogs(row: row, previous: true) }
                Button("Shell") { openShell(row: row) }
            }

            if canEditSingleObject {
                Button("Edit YAML…") { openYAML(row: row) }
            }

            Divider()

            // ── Copy ────────────────────────────────────────────────────────
            Button("Copy Name") { copyToPasteboard(row.object.name) }
            Button("Copy Namespace/Name") {
                copyToPasteboard("\(row.object.namespace ?? "")/\(row.object.name)")
            }

            // ── Workload actions ────────────────────────────────────────────
            let hasWorkloadActions = resource.supportsScale
                || resource.restartWorkload != nil
                || resource.supportsPause
                || resource.supportsSuspend
                || resource.supportsDrain

            if hasWorkloadActions {
                Divider()

                if resource.supportsScale {
                    Button("Scale…") {
                        actions.beginScale(row, currentReplicas: currentReplicas(of: row))
                    }
                }

                if resource.restartWorkload != nil {
                    Button("Restart") { actions.restartTarget = row }
                    Button("Rollout History…") {
                        actions.rolloutHistoryTarget = RolloutHistoryTarget(
                            row: row,
                            ctx: app.selectedContext,
                            ns: row.object.namespace ?? "",
                            workload: resource.restartWorkload ?? "deployments"
                        )
                    }
                }

                if resource.supportsPause {
                    Button("Pause Rollout") {
                        Task { await actions.performRolloutPause(row) }
                    }
                    Button("Resume Rollout") {
                        Task { await actions.performRolloutResume(row) }
                    }
                }

                if resource.supportsSuspend {
                    Button("Suspend") { Task { await actions.performSuspend(row) } }
                    Button("Resume") { Task { await actions.performResume(row) } }
                }

                if resource.supportsDrain {
                    Button("Drain…") { actions.drainTarget = row }
                }
            }

            // ── Danger zone ─────────────────────────────────────────────────
            if canEditSingleObject || resource.supportsCancel {
                Divider()
                if resource.supportsCancel {
                    Button("Cancel Job", role: .destructive) { actions.cancelTarget = row }
                }
                if canEditSingleObject {
                    Button("Delete", role: .destructive) { actions.deleteTarget = row }
                }
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

    private func openShell(row: TablePayload.Row) {
        openWindow(id: "shell", value: ShellWindowTarget(
            ctx: app.selectedContext,
            namespace: row.object.namespace ?? "",
            pod: row.object.name
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
                if let status = leadingStatus(for: row) {
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
        } else if isEvents && columnName == "reason" {
            Text(text)
                .foregroundStyle(ResourceColors.eventReasonColor(text))
                .fontWeight(ResourceColors.isCriticalEventReason(text) ? .medium : .regular)
                .lineLimit(1)
        } else if columnName == "port(s)" || columnName == "ports" {
            PortChipsView(value: text)
        } else {
            Text(text).lineLimit(1)
        }
    }

    /// Status dot for the leading column — events use reason severity; other
    /// resources delegate to the table model's status/ready heuristics.
    private func leadingStatus(for row: TablePayload.Row) -> String? {
        if isEvents, let reason = eventReason(for: row) {
            return ResourceColors.isCriticalEventReason(reason) ? "Failed" : "Normal"
        }
        return model.leadingStatus(for: row)
    }

    private func eventReason(for row: TablePayload.Row) -> String? {
        guard let index = model.columns.firstIndex(where: { $0.name.lowercased() == "reason" }) else {
            return nil
        }
        return row.cells[safe: index]?.displayString
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
            if model.isWatching {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .help("Live updates active")
            }
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
