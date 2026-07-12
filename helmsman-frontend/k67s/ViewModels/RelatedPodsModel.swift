import Foundation

/// Loads pods matching a workload's `spec.selector.matchLabels`.
@Observable
@MainActor
final class RelatedPodsModel {
    private(set) var payload: TablePayload?
    private(set) var isLoading = false
    private(set) var error: APIError?

    var rows: [TablePayload.Row] {
        sortedRows(from: payload)
    }

    func load(ctx: String, namespace: String, matchLabels: [String: JSONValue]) async {
        let selector = K8s.labelSelector(from: matchLabels)
        guard !selector.isEmpty else {
            payload = nil
            error = nil
            isLoading = false
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            payload = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: namespace,
                resource: "pods",
                labelSelector: selector
            )
        } catch let apiError as APIError {
            payload = nil
            self.error = apiError
        } catch {
            payload = nil
            self.error = .transport(error.localizedDescription)
        }
    }

    func reset() {
        payload = nil
        error = nil
        isLoading = false
    }

    /// Status string for the leading dot on a pod row.
    func leadingStatus(for row: TablePayload.Row) -> String? {
        guard let columns = payload?.columns else { return nil }
        let statusIndex = columns.firstIndex {
            let name = $0.name.lowercased()
            return name == "status" || name == "phase"
        }
        if let statusIndex {
            return row.cells[safe: statusIndex]?.displayString
        }
        guard let readyIndex = columns.firstIndex(where: { $0.name.lowercased() == "ready" }) else {
            return nil
        }
        let ready = row.cells[safe: readyIndex]?.displayString ?? ""
        guard ready.contains("/") else { return ready.isEmpty ? nil : ready }
        let parts = ready.split(separator: "/")
        guard parts.count == 2, let have = Int(parts[0]), let want = Int(parts[1]) else { return nil }
        return want > 0 && have >= want ? "Ready" : "Pending"
    }

    /// Secondary column text (Ready or Status) for display beside the name.
    func trailingSummary(for row: TablePayload.Row) -> String? {
        guard let columns = payload?.columns else { return nil }
        if let readyIndex = columns.firstIndex(where: { $0.name.lowercased() == "ready" }) {
            let value = row.cells[safe: readyIndex]?.displayString ?? ""
            if !value.isEmpty { return value }
        }
        if let statusIndex = columns.firstIndex(where: {
            let name = $0.name.lowercased()
            return name == "status" || name == "phase"
        }) {
            return row.cells[safe: statusIndex]?.displayString
        }
        return nil
    }

    private func sortedRows(from payload: TablePayload?) -> [TablePayload.Row] {
        guard let payload else { return [] }
        let ageIndex = payload.columns.firstIndex { $0.name.lowercased() == "age" }
        if let ageIndex {
            return payload.rows.sorted { lhs, rhs in
                let left = lhs.cells[safe: ageIndex]?.displayString ?? ""
                let right = rhs.cells[safe: ageIndex]?.displayString ?? ""
                return ageDuration(left) < ageDuration(right)
            }
        }
        return payload.rows.sorted { $0.object.name < $1.object.name }
    }

    private func ageDuration(_ age: String) -> Int {
        let trimmed = age.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("s"), let value = Int(trimmed.dropLast()) { return value }
        if trimmed.hasSuffix("m"), let value = Int(trimmed.dropLast()) { return value * 60 }
        if trimmed.hasSuffix("h"), let value = Int(trimmed.dropLast()) { return value * 3_600 }
        if trimmed.hasSuffix("d"), let value = Int(trimmed.dropLast()) { return value * 86_400 }
        return Int.max
    }
}
