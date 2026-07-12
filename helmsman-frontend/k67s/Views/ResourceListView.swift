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
    /// AppKit Table selection — cleared before payload swaps to avoid crashes.
    @State private var selectedRowID: TablePayload.Row.ID?
    /// Detail pane identity — survives benign watch reloads while the row exists.
    @State private var inspectedRowID: TablePayload.Row.ID?
    /// What the detail pane displays — may differ from the list when drilled into a related pod.
    @State private var detailFocus: DetailFocus?
    @State private var portForwardOptions: [String: [PortForwardPortOption]] = [:]
    @State private var portForwardLoadingIDs: Set<String> = []

    private var isPods: Bool { resource.isPods }
    private var isEvents: Bool { resource.resource == "events" }

    private var inspectedRow: TablePayload.Row? {
        guard let id = inspectedRowID else { return nil }
        return model.payload?.rows.first { $0.id == id }
    }

    private var podsResource: ResourceType? {
        ResourceType.all.first { $0.resource == "pods" }
    }

    /// Reload whenever context, namespace, resource, or pods filter changes.
    private var taskKey: String {
        let filterKey = resource.isPods ? (app.podsListFilter?.labelSelector ?? "") : ""
        return "\(app.selectedContext)|\(app.namespaceParam ?? "*")|\(resource.id)|\(filterKey)"
    }

    var body: some View {
        HSplitView {
            listPane
            if let focus = detailFocus {
                ResourceDetailView(
                    app: app,
                    resource: focus.resource,
                    row: focus.row,
                    parentRow: focus.parent,
                    parentResourceTitle: focus.parent != nil ? resource.title : nil,
                    onBack: focus.parent != nil ? { backToParentWorkload() } : nil,
                    onSelectPod: focus.parent == nil && resource.supportsRelatedPods
                        ? { drillToPod($0) }
                        : nil
                )
                .id("\(focus.resource.id)/\(focus.row.id)")
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
            }
        }
        .navigationTitle(resource.title)
        .searchable(text: $model.searchText, prompt: "Search \(resource.title.lowercased())…")
        .scopePickerToolbar(app: app)
        .toolbar { toolbarContent }
        .rowActionAlerts(actions)
        .task(id: taskKey) {
            actions.resource = resource
            model.willMutatePayload = { selectedRowID = nil }
            if resource.isPods, let filter = app.podsListFilter {
                model.labelSelector = filter.labelSelector
            } else {
                model.labelSelector = nil
            }
            actions.onMutated = { mutatedRowID in
                selectedRowID = nil
                if mutatedRowID == inspectedRowID {
                    inspectedRowID = nil
                    detailFocus = nil
                }
                model.cancelPendingReload()
                Task { await reloadAndSyncSelection() }
            }
            actions.onPortForwardStarted = { _ in
                Task {
                    await app.portForwards.refresh(ctx: app.selectedContext)
                    app.selectedDestination = .portForwards
                }
            }
            selectedRowID = nil
            inspectedRowID = nil
            detailFocus = nil
            // Namespace/context change: clear payload without mounting an empty
            // TableColumnForEach (that AttributeGraph path crashes).
            if model.payload != nil {
                model.reset()
            }
            await reloadAndSyncSelection()
            await model.watch(ctx: app.selectedContext, ns: app.namespaceParam, resource: resource)
        }
    }

    @ViewBuilder
    private var listPane: some View {
        VStack(spacing: 0) {
            if resource.isPods, let filter = app.podsListFilter {
                PodsListFilterBar(
                    title: "Pods for \(filter.sourceTitle)",
                    onClear: { app.clearPodsListFilter() }
                )
                Divider()
            }

            if model.payload == nil {
                if let error = model.error {
                    ErrorStateView(error: error) {
                        Task { await reloadAndSyncSelection() }
                    }
                } else {
                    ResourceListSkeleton(columnCount: 4)
                }
            } else {
                table
                    .overlay {
                        if model.payload?.rows.isEmpty == true {
                            ContentUnavailableView("No \(resource.title)", systemImage: resource.symbol)
                        }
                    }
            }
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
        .onChange(of: selectedRowID) { _, id in
            guard resource.supportsPortForward,
                  let id,
                  let row = model.payload?.rows.first(where: { $0.id == id })
            else { return }
            Task { await loadPortForwardOptions(for: row) }
        }
        .onChange(of: model.visibleColumns.map(\.id)) { _, _ in
            // Column structure changed — NSTableView cannot keep a valid selection index.
            selectedRowID = nil
        }
        .onChange(of: model.rows.map(\.id)) { _, ids in
            if let selected = selectedRowID, !ids.contains(selected) {
                selectedRowID = nil
            }
            if let inspected = inspectedRowID {
                if !ids.contains(inspected) {
                    inspectedRowID = nil
                    detailFocus = nil
                } else if selectedRowID == nil {
                    selectedRowID = inspected
                }
            }
        }
        .contextMenu(forSelectionType: TablePayload.Row.ID.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            inspect(ids.first)
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<TablePayload.Row.ID>) -> some View {
        if let id = ids.first, let row = model.payload?.rows.first(where: { $0.id == id }) {
            let hasNamespace = !(row.object.namespace ?? "").isEmpty
            let canEditSingleObject = hasNamespace || resource.scope == .cluster

            // ── Inspect / Logs ──────────────────────────────────────────────
            Button("Inspect") { inspect(id) }

            if resource.supportsRelatedPods {
                Button("Show Pods") {
                    Task { await showPodsForRow(row) }
                }
            }

            if resource.supportsLogs {
                Button("Logs") { openLogs(row: row, previous: false) }
                Button("Previous Logs") { openLogs(row: row, previous: true) }
            }

            if isPods {
                Button("Shell") { openShell(row: row) }
            }

            if resource.supportsPortForward, hasNamespace {
                // Start fetch as soon as the context menu builds. Waiting for
                // Menu.onAppear races the first paint and shows a false "No ports".
                let _ = schedulePortForwardLoad(for: row)
                Menu("Port Forward") {
                    portForwardSubmenu(for: row)
                }
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
                || resource.supportsTriggerCronJob
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

                if resource.supportsTriggerCronJob {
                    Button("Trigger Now…") { actions.triggerTarget = row }
                }

                if resource.supportsDrain {
                    Button("Drain…") { actions.drainTarget = row }
                }
            }

            if resource.supportsResize {
                Divider()
                Button("Resize…") {
                    actions.beginResize(pvcResizeTarget(for: row))
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
                    if resource.supportsCascadeDelete {
                        Button("Delete with Options…", role: .destructive) {
                            actions.beginDeleteWithOptions(row)
                        }
                    }
                    Button("Force Delete…", role: .destructive) { actions.forceDeleteTarget = row }
                }
            }
        }
    }

    private func inspect(_ id: TablePayload.Row.ID?) {
        selectedRowID = id
        inspectedRowID = id
        if let id, let row = model.payload?.rows.first(where: { $0.id == id }) {
            detailFocus = DetailFocus(resource: resource, row: row, parent: nil)
        } else {
            detailFocus = nil
        }
    }

    private func drillToPod(_ podRow: TablePayload.Row) {
        guard let parentRow = inspectedRow,
              let podsResource else { return }
        detailFocus = DetailFocus(resource: podsResource, row: podRow, parent: parentRow)
    }

    private func backToParentWorkload() {
        guard let parent = detailFocus?.parent else { return }
        detailFocus = DetailFocus(resource: resource, row: parent, parent: nil)
    }

    private func showPodsForRow(_ row: TablePayload.Row) async {
        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: app.selectedContext,
                ns: row.object.namespace,
                resource: resource.resource,
                name: row.object.name
            )
            guard let labels = object["spec"]?["selector"]?["matchLabels"]?.objectValue,
                  !labels.isEmpty else {
                actions.actionError = .transport("This workload has no pod selector.")
                return
            }
            app.showPods(for: resource, row: row, matchLabels: labels)
        } catch let apiError as APIError {
            actions.actionError = apiError
        } catch {
            actions.actionError = .transport(error.localizedDescription)
        }
    }

    private func openLogs(row: TablePayload.Row, previous: Bool) {
        let namespace = row.object.namespace ?? ""
        let target: LogWindowTarget
        if resource.resource == "jobs.batch" {
            target = LogWindowTarget(
                ctx: app.selectedContext,
                namespace: namespace,
                pod: nil,
                job: row.object.name,
                previous: previous
            )
        } else {
            target = LogWindowTarget(
                ctx: app.selectedContext,
                namespace: namespace,
                pod: row.object.name,
                job: nil,
                previous: previous
            )
        }
        openWindow(id: "logs", value: target)
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

    /// Kicks off a port-option fetch without blocking menu construction.
    private func schedulePortForwardLoad(for row: TablePayload.Row) -> Bool {
        let rowID = row.id
        guard portForwardOptions[rowID] == nil, !portForwardLoadingIDs.contains(rowID) else {
            return false
        }
        Task { await loadPortForwardOptions(for: row) }
        return true
    }

    @ViewBuilder
    private func portForwardSubmenu(for row: TablePayload.Row) -> some View {
        // nil = not loaded yet → Loading. [] = loaded with no declared ports.
        if let options = portForwardOptions[row.id] {
            if options.isEmpty {
                Button("No declared ports") {}.disabled(true)
            } else {
                ForEach(options) { option in
                    Button(option.label) {
                        actions.beginPortForward(PortForwardTarget(
                            row: row,
                            ctx: app.selectedContext,
                            resource: resource,
                            portOption: option
                        ))
                    }
                }
            }
            Divider()
            Button("Custom Port…") {
                actions.beginPortForward(PortForwardTarget(
                    row: row,
                    ctx: app.selectedContext,
                    resource: resource,
                    portOption: .custom
                ))
            }
        } else {
            Button("Loading…") {}.disabled(true)
                .task(id: row.id) {
                    await loadPortForwardOptions(for: row)
                }
        }
    }

    private func loadPortForwardOptions(for row: TablePayload.Row) async {
        let rowID = row.id
        if portForwardOptions[rowID] != nil { return }
        if portForwardLoadingIDs.contains(rowID) { return }
        portForwardLoadingIDs.insert(rowID)
        defer { portForwardLoadingIDs.remove(rowID) }
        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: app.selectedContext,
                ns: row.object.namespace,
                resource: resource.resource,
                name: row.object.name
            )
            let options: [PortForwardPortOption]
            if resource.resource == "pods" {
                options = PortForwardPortParser.podPorts(from: object)
            } else {
                options = PortForwardPortParser.servicePorts(from: object)
            }
            portForwardOptions[rowID] = options
        } catch {
            // Leave nil so the next open retries instead of caching a false empty.
        }
    }

    /// Best-effort current replica count for the scale modal, parsed from a
    /// "Ready" column cell like "1/1" (uses the desired count after the slash).
    private func currentReplicas(of row: TablePayload.Row) -> String {
        guard let readyIndex = model.columns.firstIndex(where: { $0.name.lowercased() == "ready" }),
              let cell = row.cells[safe: readyIndex]?.displayString
        else { return "" }
        return cell.split(separator: "/").last.map(String.init) ?? cell
    }

    private func pvcResizeTarget(for row: TablePayload.Row) -> ResizePVCTarget {
        let request = tableCell(row, named: ["Request"]) ?? "—"
        let parsed = ResizePVCTarget.parseQuantity(request)
        return ResizePVCTarget(
            row: row,
            currentRequest: request,
            capacity: tableCell(row, named: ["Capacity"]) ?? "—",
            storageClass: tableCell(row, named: ["Storage Class", "StorageClass", "Class"]) ?? "—",
            initialValue: parsed.value,
            initialUnit: parsed.unit
        )
    }

    private func tableCell(_ row: TablePayload.Row, named names: [String]) -> String? {
        for name in names {
            if let index = model.columns.firstIndex(where: { $0.name.lowercased() == name.lowercased() }),
               let value = row.cells[safe: index]?.displayString,
               !value.isEmpty {
                return value
            }
        }
        return nil
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
                Task { await reloadAndSyncSelection() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh")
        }
    }

    private func reloadAndSyncSelection() async {
        await model.load(ctx: app.selectedContext, ns: app.namespaceParam, resource: resource)
        if let count = model.payload?.rows.count {
            app.sidebarCounts.set(resource: resource.resource, count: count)
        }
        syncSelectionAfterReload()
    }

    private func syncSelectionAfterReload() {
        let ids = Set(model.payload?.rows.map(\.id) ?? [])
        guard let inspected = inspectedRowID else { return }
        if ids.contains(inspected) {
            selectedRowID = inspected
            if detailFocus?.parent == nil,
               let row = model.payload?.rows.first(where: { $0.id == inspected }) {
                detailFocus = DetailFocus(resource: resource, row: row, parent: nil)
            }
        } else {
            inspectedRowID = nil
            detailFocus = nil
        }
    }
}
