import Foundation

/// The Kubernetes server-side Table format returned by every list endpoint:
/// server-defined columns plus rows of heterogeneous cells. Mirrors what
/// `kubectl get` prints, which lets one view render any resource type.
struct TablePayload: Decodable, Sendable {
    let columns: [Column]
    let rows: [Row]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decodeIfPresent([Column].self, forKey: .columns) ?? []
        rows = try container.decodeIfPresent([Row].self, forKey: .rows) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case columns, rows
    }

    struct Column: Decodable, Sendable, Hashable {
        let name: String
        let type: String
        let priority: Int

        /// `priority == 0` columns are always shown; `> 0` are "wide" columns.
        var isPrimary: Bool { priority == 0 }
    }

    struct Row: Decodable, Sendable, Identifiable {
        /// Heterogeneous, aligned 1:1 with `columns`.
        let cells: [JSONValue]
        /// Stub used to build follow-up get/yaml/delete URLs — never parse cells.
        let object: ObjectStub

        /// Stable identity for table selection — must not change between reloads.
        /// UIDs from the server can appear on a later fetch after being absent on
        /// the first, which would reshuffle IDs and crash NSTableView selection.
        var id: String {
            let namespace = object.namespace ?? ""
            if namespace.isEmpty {
                return object.name
            }
            return "\(namespace)/\(object.name)"
        }
    }

    struct ObjectStub: Decodable, Sendable, Hashable {
        let namespace: String?
        let name: String
        let uid: String?
    }
}
