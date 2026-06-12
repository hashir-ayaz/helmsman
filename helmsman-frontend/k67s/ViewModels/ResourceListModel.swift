import SwiftUI

/// Drives one generic resource list: loads a `TablePayload` and exposes the
/// columns/rows the table renders, with search and a wide-column toggle.
@Observable
final class ResourceListModel {
    private(set) var payload: TablePayload?
    private(set) var isLoading = false
    var error: APIError?
    var searchText = ""
    var showWide = false

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

    func load(ctx: String, ns: String?, resource: ResourceType) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let effectiveNS = resource.scope == .cluster ? nil : ns
        do {
            payload = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: effectiveNS,
                resource: resource.resource
            )
        } catch let apiError as APIError {
            error = apiError
            payload = nil
        } catch {
            self.error = .transport(error.localizedDescription)
            payload = nil
        }
    }
}
