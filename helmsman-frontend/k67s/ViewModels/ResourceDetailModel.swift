import SwiftUI

/// Loads the full raw object and (lazily) the YAML for one selected resource.
@Observable
final class ResourceDetailModel {
    struct RelatedEvent: Identifiable {
        let id: String
        let type: String
        let reason: String
        let message: String
        let age: String
    }

    private(set) var object: JSONValue?
    private(set) var yaml: String?
    private(set) var events: [RelatedEvent] = []
    private(set) var isLoadingObject = false
    private(set) var isLoadingYAML = false
    private(set) var isLoadingEvents = false
    var error: APIError?

    func loadObject(ctx: String, ns: String?, resource: ResourceType, name: String) async {
        guard object == nil else { return }
        isLoadingObject = true
        defer { isLoadingObject = false }
        do {
            object = try await KubeAPIClient.shared.getObject(
                ctx: ctx, ns: ns, resource: resource.resource, name: name
            )
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func loadYAML(ctx: String, ns: String?, resource: ResourceType, name: String) async {
        guard yaml == nil else { return }
        isLoadingYAML = true
        defer { isLoadingYAML = false }
        do {
            yaml = try await KubeAPIClient.shared.getYAML(
                ctx: ctx, ns: ns, resource: resource.resource, name: name
            )
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func loadEvents(ctx: String, ns: String?, kind: String, name: String) async {
        guard let ns else { return }
        isLoadingEvents = true
        defer { isLoadingEvents = false }
        let selector = "involvedObject.name=\(name),involvedObject.kind=\(kind)"
        do {
            let table = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: ns,
                resource: "events",
                fieldSelector: selector
            )
            events = Self.parseEventsTable(table)
        } catch {
            // Events are supplementary — keep the overview usable if this fails.
            events = []
        }
    }

    private static func parseEventsTable(_ table: TablePayload) -> [RelatedEvent] {
        table.rows.map { row in
            RelatedEvent(
                id: row.id,
                type: cell(row, columns: table.columns, named: ["Type"]) ?? "",
                reason: cell(row, columns: table.columns, named: ["Reason"]) ?? "—",
                message: cell(row, columns: table.columns, named: ["Message"]) ?? "",
                age: cell(row, columns: table.columns, named: ["Last Seen", "Age"]) ?? ""
            )
        }
    }

    private static func cell(
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
}
