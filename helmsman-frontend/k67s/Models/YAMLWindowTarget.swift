import Foundation

/// Identifies the resource whose YAML a separate editor window edits. `Codable &
/// Hashable` because SwiftUI's `WindowGroup(for:)` carries it as the window's value.
struct YAMLWindowTarget: Codable, Hashable, Identifiable {
    let ctx: String
    let namespace: String
    let resource: String
    let name: String

    var id: String { "\(ctx)/\(namespace)/\(resource)/\(name)" }

    var windowTitle: String { "\(name) — YAML" }
}
