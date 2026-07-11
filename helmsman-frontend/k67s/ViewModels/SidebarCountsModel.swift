import Foundation

/// Per-resource row counts for the sidebar, scoped to the current context/namespace.
@Observable
@MainActor
final class SidebarCountsModel {
    private(set) var counts: [String: Int] = [:]
    private var loadGeneration = 0

    func set(resource: String, count: Int) {
        counts[resource] = count
    }

    /// Fetches table row counts for every catalog resource in parallel.
    func load(ctx: String, namespaceParam: String?) async {
        loadGeneration += 1
        let generation = loadGeneration

        let results = await withTaskGroup(of: (String, Int?).self) { group in
            for resource in ResourceType.all {
                group.addTask {
                    let effectiveNS = resource.scope == .cluster ? nil : namespaceParam
                    do {
                        let table = try await KubeAPIClient.shared.listResources(
                            ctx: ctx,
                            ns: effectiveNS,
                            resource: resource.resource
                        )
                        return (resource.resource, table.rows.count)
                    } catch {
                        return (resource.resource, nil)
                    }
                }
            }

            var collected: [String: Int] = [:]
            for await (key, count) in group {
                if let count { collected[key] = count }
            }
            return collected
        }

        guard generation == loadGeneration else { return }
        counts = results
    }
}
