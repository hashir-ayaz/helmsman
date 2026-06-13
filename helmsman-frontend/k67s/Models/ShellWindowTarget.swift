struct ShellWindowTarget: Codable, Hashable, Identifiable {
    let ctx: String
    let namespace: String
    let pod: String

    var id: String { "\(ctx)/\(namespace)/\(pod)" }

    var windowTitle: String { "\(pod) — Shell" }
}
