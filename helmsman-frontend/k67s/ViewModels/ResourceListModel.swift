import SwiftUI

/// Drives one generic resource list: loads a `TablePayload` and exposes the
/// columns/rows the table renders, with search and a wide-column toggle.
@Observable
@MainActor
final class ResourceListModel {
    private(set) var payload: TablePayload?
    private(set) var isLoading = false
    var error: APIError?
    var searchText = ""
    var showWide = false
    private(set) var isWatching = false
    private var reloadWork: Task<Void, Never>?
    private var loadGeneration = 0

    /// Called on the main actor immediately before `payload` is replaced with a
    /// successful fetch. Use to clear AppKit Table selection before row diffs.
    var willMutatePayload: (@MainActor () -> Void)?

    /// Cancels any debounced watch-triggered reload. Call before an
    /// immediate mutation-triggered reload to prevent a stale second load.
    func cancelPendingReload() {
        reloadWork?.cancel()
        reloadWork = nil
    }

    var columns: [TablePayload.Column] {
        payload?.columns ?? []
    }

    /// A column paired with its original index into a row's `cells`. Identity is
    /// the original index so SwiftUI diffs columns correctly as resources change.
    struct VisibleColumn: Identifiable {
        let id: Int
        let column: TablePayload.Column
    }

    /// Columns to display: priority-0 always, the rest when `showWide`.
    var visibleColumns: [VisibleColumn] {
        columns.indices
            .filter { showWide || columns[$0].isPrimary }
            .map { VisibleColumn(id: $0, column: columns[$0]) }
    }

    /// Index of a status-like column, used to color the leading status dot.
    var statusColumnIndex: Int? {
        columns.firstIndex { ["status", "phase"].contains($0.name.lowercased()) }
    }

    private func columnIndex(named name: String) -> Int? {
        columns.firstIndex { $0.name.lowercased() == name }
    }

    /// The status string driving the leading dot, or `nil` for no dot. Uses an
    /// explicit Status/Phase column when present (pods), otherwise derives
    /// readiness from a "Ready" column ("X/Y", or a count compared to "Desired").
    func leadingStatus(for row: TablePayload.Row) -> String? {
        if let index = statusColumnIndex {
            return row.cells[safe: index]?.displayString
        }
        guard let readyIndex = columnIndex(named: "ready") else { return nil }
        let ready = row.cells[safe: readyIndex]?.displayString ?? ""

        if ready.contains("/") {
            let parts = ready.split(separator: "/")
            guard parts.count == 2, let have = Int(parts[0]), let want = Int(parts[1]) else { return nil }
            return want > 0 && have >= want ? "Ready" : "Pending"
        }

        guard let desiredIndex = columnIndex(named: "desired"),
              let have = Int(ready),
              let want = Int(row.cells[safe: desiredIndex]?.displayString ?? "")
        else { return nil }
        return want > 0 && have >= want ? "Ready" : "Pending"
    }

    var rows: [TablePayload.Row] {
        let all = payload?.rows ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { row in
            row.object.name.localizedCaseInsensitiveContains(searchText)
                || row.cells.contains { $0.displayString.localizedCaseInsensitiveContains(searchText) }
        }
    }

    /// Loads the table payload. Concurrent callers coalesce: only one network
    /// fetch runs at a time; newer requests trigger a follow-up load when the
  /// current one finishes.
    func load(ctx: String, ns: String?, resource: ResourceType) async {
        loadGeneration += 1
        var generation = loadGeneration

        repeat {
            await performLoad(ctx: ctx, ns: ns, resource: resource)
            if generation == loadGeneration { return }
            generation = loadGeneration
        } while true
    }

    private func performLoad(ctx: String, ns: String?, resource: ResourceType) async {
        isLoading = true
        if payload == nil { error = nil }
        defer { isLoading = false }

        let effectiveNS = resource.scope == .cluster ? nil : ns
        do {
            let newPayload = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: effectiveNS,
                resource: resource.resource
            )
            willMutatePayload?()
            payload = newPayload
            error = nil
        } catch let apiError as APIError {
            error = apiError
            if payload == nil {
                payload = nil
            }
        } catch {
            self.error = .transport(error.localizedDescription)
            if payload == nil {
                payload = nil
            }
        }
    }

    /// Runs until the enclosing Task is cancelled. Reconnects the watch stream
    /// automatically after any error or server-side close.
    func watch(ctx: String, ns: String?, resource: ResourceType) async {
        isWatching = true
        defer {
            isWatching = false
            reloadWork?.cancel()
            reloadWork = nil
        }
        let effectiveNS = resource.scope == .cluster ? nil : ns
        while !Task.isCancelled {
            let stream = KubeAPIClient.shared.streamWatch(
                ctx: ctx,
                ns: effectiveNS,
                resource: resource.resource
            )
            do {
                for try await _ in stream {
                    scheduleReload(ctx: ctx, ns: ns, resource: resource)
                }
            } catch is CancellationError {
                return
            } catch {
                // ignore transport errors — will reconnect after backoff
            }
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return // cancelled during backoff
            }
        }
    }

    private func scheduleReload(ctx: String, ns: String?, resource: ResourceType) {
        reloadWork?.cancel()
        reloadWork = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard let self else { return }
            await self.load(ctx: ctx, ns: ns, resource: resource)
        }
    }
}
