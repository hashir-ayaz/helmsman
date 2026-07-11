import Foundation

/// Aggregates cluster-wide summary data from parallel generic list calls.
@Observable
@MainActor
final class ClusterOverviewModel {
    struct SummaryCard: Identifiable {
        let id: String
        let title: String
        let count: Int?
        let symbol: String
        let resource: ResourceType
        let errorMessage: String?
    }

    struct WorkloadBar: Identifiable {
        let id: String
        let title: String
        let resource: ResourceType
        let buckets: [StatusBucket]
        let total: Int
        let errorMessage: String?

        struct StatusBucket: Identifiable {
            let id: String
            let label: String
            let count: Int
            let color: StatusBucketColor
        }

        enum StatusBucketColor {
            case running, pending, failed, completed, other
        }

        var healthyFraction: Double {
            guard total > 0 else { return 0 }
            let healthy = buckets.filter {
                $0.color == .running || $0.color == .completed
            }.map(\.count).reduce(0, +)
            return Double(healthy) / Double(total)
        }
    }

    struct WarningEvent: Identifiable {
        let id: String
        let reason: String
        let object: String
        let message: String
        let age: String
    }

    struct NodeRow: Identifiable {
        let id: String
        let name: String
        let status: String
        let roles: String
        let age: String
        let version: String
    }

    private(set) var summaryCards: [SummaryCard] = []
    private(set) var workloadBars: [WorkloadBar] = []
    private(set) var warningEvents: [WarningEvent] = []
    private(set) var nodes: [NodeRow] = []
    private(set) var isLoading = false
    private(set) var warningsError: String?
    private(set) var nodesError: String?

    private static let maxWarnings = 20

    /// Clears dashboard data so context switches show skeleton placeholders.
    func reset() {
        summaryCards = []
        workloadBars = []
        warningEvents = []
        nodes = []
        warningsError = nil
        nodesError = nil
        isLoading = false
    }

    func load(ctx: String) async {
        isLoading = true
        defer { isLoading = false }

        async let nodesResult = fetchTable(ctx: ctx, resource: "nodes", ns: nil)
        async let podsResult = fetchTable(ctx: ctx, resource: "pods", ns: nil)
        async let namespacesResult = fetchTable(ctx: ctx, resource: "namespaces", ns: nil)
        async let deploymentsResult = fetchTable(ctx: ctx, resource: "deployments.apps", ns: nil)
        async let daemonSetsResult = fetchTable(ctx: ctx, resource: "daemonsets.apps", ns: nil)
        async let statefulSetsResult = fetchTable(ctx: ctx, resource: "statefulsets.apps", ns: nil)
        async let jobsResult = fetchTable(ctx: ctx, resource: "jobs.batch", ns: nil)
        async let cronJobsResult = fetchTable(ctx: ctx, resource: "cronjobs.batch", ns: nil)
        async let eventsResult = fetchTable(
            ctx: ctx,
            resource: "events",
            ns: nil,
            fieldSelector: "type=Warning"
        )

        let nodes = await nodesResult
        let pods = await podsResult
        let namespaces = await namespacesResult
        let deployments = await deploymentsResult
        let daemonSets = await daemonSetsResult
        let statefulSets = await statefulSetsResult
        let jobs = await jobsResult
        let cronJobs = await cronJobsResult
        let events = await eventsResult

        summaryCards = [
            makeSummaryCard(
                id: "nodes",
                title: "Nodes",
                symbol: "cpu",
                resourceKey: "nodes",
                result: nodes
            ),
            makeSummaryCard(
                id: "pods",
                title: "Pods",
                symbol: "shippingbox",
                resourceKey: "pods",
                result: pods
            ),
            makeSummaryCard(
                id: "namespaces",
                title: "Namespaces",
                symbol: "folder",
                resourceKey: "namespaces",
                result: namespaces
            ),
        ]

        workloadBars = [
            makePodBar(result: pods),
            makeReadyBar(title: "Deployments", resourceKey: "deployments.apps", result: deployments),
            makeReadyBar(title: "DaemonSets", resourceKey: "daemonsets.apps", result: daemonSets),
            makeReadyBar(title: "StatefulSets", resourceKey: "statefulsets.apps", result: statefulSets),
            makeJobBar(result: jobs),
            makeCronJobBar(result: cronJobs),
        ]

        switch events {
        case .success(let table):
            warningsError = nil
            warningEvents = parseWarningEvents(table).prefix(Self.maxWarnings).map { $0 }
        case .failure(let error):
            warningsError = error.errorDescription
            warningEvents = []
        }

        switch nodes {
        case .success(let table):
            nodesError = nil
            self.nodes = parseNodes(table)
        case .failure(let error):
            nodesError = error.errorDescription
            self.nodes = []
        }
    }

    // MARK: - Fetch

    private func fetchTable(
        ctx: String,
        resource: String,
        ns: String?,
        fieldSelector: String? = nil
    ) async -> Result<TablePayload, APIError> {
        do {
            let table = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: ns,
                resource: resource,
                fieldSelector: fieldSelector
            )
            return .success(table)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    // MARK: - Summary cards

    private func makeSummaryCard(
        id: String,
        title: String,
        symbol: String,
        resourceKey: String,
        result: Result<TablePayload, APIError>
    ) -> SummaryCard {
        guard let resource = ResourceType.all.first(where: { $0.resource == resourceKey }) else {
            return SummaryCard(
                id: id, title: title, count: nil, symbol: symbol,
                resource: ResourceType.all[0], errorMessage: "Unknown resource"
            )
        }
        switch result {
        case .success(let table):
            return SummaryCard(
                id: id, title: title, count: table.rows.count, symbol: symbol,
                resource: resource, errorMessage: nil
            )
        case .failure(let error):
            return SummaryCard(
                id: id, title: title, count: nil, symbol: symbol,
                resource: resource, errorMessage: error.errorDescription
            )
        }
    }

    // MARK: - Workload bars

    private func makePodBar(result: Result<TablePayload, APIError>) -> WorkloadBar {
        guard let resource = ResourceType.all.first(where: { $0.resource == "pods" }) else {
            return emptyBar(id: "pods", title: "Pods", resource: ResourceType.all[0], message: nil)
        }
        switch result {
        case .success(let table):
            var buckets: [String: Int] = [:]
            for row in table.rows {
                let status = TableParsing.cell(row, columns: table.columns, named: ["Status", "Phase"]) ?? "Unknown"
                let key = Self.podBucket(status)
                buckets[key, default: 0] += 1
            }
            return WorkloadBar(
                id: "pods",
                title: "Pods",
                resource: resource,
                buckets: Self.orderedBuckets(from: buckets),
                total: table.rows.count,
                errorMessage: nil
            )
        case .failure(let error):
            return emptyBar(id: "pods", title: "Pods", resource: resource, message: error.errorDescription)
        }
    }

    private func makeReadyBar(
        title: String,
        resourceKey: String,
        result: Result<TablePayload, APIError>
    ) -> WorkloadBar {
        guard let resource = ResourceType.all.first(where: { $0.resource == resourceKey }) else {
            return emptyBar(id: resourceKey, title: title, resource: ResourceType.all[0], message: nil)
        }
        switch result {
        case .success(let table):
            var running = 0
            var pending = 0
            for row in table.rows {
                let ready = TableParsing.cell(row, columns: table.columns, named: ["Ready"]) ?? ""
                if TableParsing.isWorkloadReady(ready) {
                    running += 1
                } else {
                    pending += 1
                }
            }
            var buckets: [String: Int] = [:]
            if running > 0 { buckets["Running"] = running }
            if pending > 0 { buckets["Pending"] = pending }
            return WorkloadBar(
                id: resourceKey,
                title: title,
                resource: resource,
                buckets: Self.orderedBuckets(from: buckets),
                total: table.rows.count,
                errorMessage: nil
            )
        case .failure(let error):
            return emptyBar(id: resourceKey, title: title, resource: resource, message: error.errorDescription)
        }
    }

    private func makeJobBar(result: Result<TablePayload, APIError>) -> WorkloadBar {
        guard let resource = ResourceType.all.first(where: { $0.resource == "jobs.batch" }) else {
            return emptyBar(id: "jobs", title: "Jobs", resource: ResourceType.all[0], message: nil)
        }
        switch result {
        case .success(let table):
            var buckets: [String: Int] = [:]
            for row in table.rows {
                let status = TableParsing.cell(row, columns: table.columns, named: ["Status", "Conditions"]) ?? "Unknown"
                let key = Self.jobBucket(status)
                buckets[key, default: 0] += 1
            }
            return WorkloadBar(
                id: "jobs",
                title: "Jobs",
                resource: resource,
                buckets: Self.orderedBuckets(from: buckets),
                total: table.rows.count,
                errorMessage: nil
            )
        case .failure(let error):
            return emptyBar(id: "jobs", title: "Jobs", resource: resource, message: error.errorDescription)
        }
    }

    private func makeCronJobBar(result: Result<TablePayload, APIError>) -> WorkloadBar {
        guard let resource = ResourceType.all.first(where: { $0.resource == "cronjobs.batch" }) else {
            return emptyBar(id: "cronjobs", title: "CronJobs", resource: ResourceType.all[0], message: nil)
        }
        switch result {
        case .success(let table):
            var active = 0
            var idle = 0
            for row in table.rows {
                let activeText = TableParsing.cell(row, columns: table.columns, named: ["Active"]) ?? "0"
                let count = Int(activeText.trimmingCharacters(in: .whitespaces)) ?? 0
                if count > 0 {
                    active += 1
                } else {
                    idle += 1
                }
            }
            var buckets: [String: Int] = [:]
            if active > 0 { buckets["Active"] = active }
            if idle > 0 { buckets["Idle"] = idle }
            return WorkloadBar(
                id: "cronjobs",
                title: "CronJobs",
                resource: resource,
                buckets: Self.orderedBuckets(from: buckets),
                total: table.rows.count,
                errorMessage: nil
            )
        case .failure(let error):
            return emptyBar(id: "cronjobs", title: "CronJobs", resource: resource, message: error.errorDescription)
        }
    }

    private func emptyBar(
        id: String,
        title: String,
        resource: ResourceType,
        message: String?
    ) -> WorkloadBar {
        WorkloadBar(
            id: id, title: title, resource: resource,
            buckets: [], total: 0, errorMessage: message
        )
    }

    // MARK: - Events + nodes

    private func parseWarningEvents(_ table: TablePayload) -> [WarningEvent] {
        table.rows.map { row in
            let reason = TableParsing.cell(row, columns: table.columns, named: ["Reason"]) ?? "—"
            let object = TableParsing.cell(row, columns: table.columns, named: ["Object", "Source"]) ?? row.object.name
            let message = TableParsing.cell(row, columns: table.columns, named: ["Message"]) ?? ""
            let age = TableParsing.cell(row, columns: table.columns, named: ["Last Seen", "Age"]) ?? ""
            return WarningEvent(
                id: row.id,
                reason: reason,
                object: object,
                message: message,
                age: age
            )
        }
    }

    private func parseNodes(_ table: TablePayload) -> [NodeRow] {
        table.rows.map { row in
            NodeRow(
                id: row.id,
                name: row.object.name,
                status: TableParsing.cell(row, columns: table.columns, named: ["Status"]) ?? "Unknown",
                roles: TableParsing.cell(row, columns: table.columns, named: ["Roles"]) ?? "—",
                age: TableParsing.cell(row, columns: table.columns, named: ["Age"]) ?? "",
                version: TableParsing.cell(row, columns: table.columns, named: ["Version"]) ?? ""
            )
        }
    }

    // MARK: - Bucketing helpers

    private static func podBucket(_ status: String) -> String {
        switch status.lowercased() {
        case "running": return "Running"
        case "pending": return "Pending"
        case "succeeded", "completed": return "Completed"
        case "failed", "error": return "Failed"
        default: return status.isEmpty ? "Unknown" : status
        }
    }

    private static func jobBucket(_ status: String) -> String {
        let lower = status.lowercased()
        if lower.contains("complete") { return "Completed" }
        if lower.contains("fail") { return "Failed" }
        if lower.contains("running") || lower.contains("active") { return "Running" }
        return status.isEmpty ? "Unknown" : status
    }

    private static func orderedBuckets(from buckets: [String: Int]) -> [WorkloadBar.StatusBucket] {
        let order = ["Running", "Completed", "Active", "Pending", "Idle", "Failed", "Unknown"]
        return buckets
            .sorted { lhs, rhs in
                let li = order.firstIndex(of: lhs.key) ?? order.count
                let ri = order.firstIndex(of: rhs.key) ?? order.count
                if li != ri { return li < ri }
                return lhs.key < rhs.key
            }
            .map { key, count in
                WorkloadBar.StatusBucket(
                    id: key,
                    label: key,
                    count: count,
                    color: bucketColor(for: key)
                )
            }
    }

    private static func bucketColor(for label: String) -> WorkloadBar.StatusBucketColor {
        switch label.lowercased() {
        case "running", "active": return .running
        case "completed": return .completed
        case "pending", "idle": return .pending
        case "failed": return .failed
        default: return .other
        }
    }
}

// MARK: - Table cell parsing

private enum TableParsing {
    static func cell(
        _ row: TablePayload.Row,
        columns: [TablePayload.Column],
        named names: [String]
    ) -> String? {
        for name in names {
            if let index = columns.firstIndex(where: { $0.name.lowercased() == name.lowercased() }),
               let value = row.cells[safe: index]?.displayString,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func isWorkloadReady(_ ready: String) -> Bool {
        if ready.contains("/") {
            let parts = ready.split(separator: "/")
            guard parts.count == 2,
                  let have = Int(parts[0]),
                  let want = Int(parts[1]) else { return false }
            return want > 0 && have >= want
        }
        return ready.lowercased() == "true" || ready == "1"
    }
}
