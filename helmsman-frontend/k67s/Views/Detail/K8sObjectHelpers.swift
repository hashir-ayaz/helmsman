import Foundation

/// Pure derivations from an unstructured Kubernetes object (`JSONValue`).
/// Kept free of SwiftUI so it stays unit-testable if a test target is added.
enum K8s {
    private static let iso8601 = ISO8601DateFormatter()

    /// Compact age like "17h", "2d", "5m" from an RFC3339 timestamp.
    static func age(from timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        guard let date = iso8601.date(from: timestamp) else { return nil }
        let secs = Int(Date().timeIntervalSince(date))
        if secs <= 0 { return "0s" }
        let d = secs / 86400, h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60, s = secs % 60
        if d > 0 { return h > 0 ? "\(d)d\(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Controlling owner as "Kind/name", preferring the controller=true ref.
    static func controlledBy(_ object: JSONValue) -> String? {
        guard let refs = object["metadata"]?["ownerReferences"]?.arrayValue,
              !refs.isEmpty else { return nil }
        let ref = refs.first(where: { $0["controller"]?.boolValue == true }) ?? refs[0]
        guard let kind = ref["kind"]?.stringValue,
              let name = ref["name"]?.stringValue else { return nil }
        return "\(kind)/\(name)"
    }

    /// Pod ready string "1/2": ready container count / total spec containers.
    static func podReady(_ object: JSONValue) -> String? {
        guard let spec = object["spec"]?["containers"]?.arrayValue else { return nil }
        let statuses = object["status"]?["containerStatuses"]?.arrayValue ?? []
        let ready = statuses.filter { $0["ready"]?.boolValue == true }.count
        return "\(ready)/\(spec.count)"
    }

    /// Sum of restart counts across container statuses.
    static func podRestarts(_ object: JSONValue) -> Int {
        let statuses = object["status"]?["containerStatuses"]?.arrayValue ?? []
        return statuses.reduce(0) { $0 + ($1["restartCount"]?.intValue ?? 0) }
    }

    /// A spec container paired with its matching status (by name).
    struct ContainerPair: Identifiable {
        let name: String
        let spec: JSONValue
        let status: JSONValue?
        var id: String { name }
    }

    /// Joins spec.containers[] with status.containerStatuses[] by name.
    static func containerPairs(_ object: JSONValue) -> [ContainerPair] {
        guard let spec = object["spec"]?["containers"]?.arrayValue else { return [] }
        let statuses = object["status"]?["containerStatuses"]?.arrayValue ?? []
        var byName: [String: JSONValue] = [:]
        for st in statuses {
            if let n = st["name"]?.stringValue { byName[n] = st }
        }
        return spec.compactMap { container in
            guard let name = container["name"]?.stringValue else { return nil }
            return ContainerPair(name: name, spec: container, status: byName[name])
        }
    }

    /// Human label for a container's runtime state.
    static func containerStateLabel(_ status: JSONValue?) -> String {
        guard let state = status?["state"]?.objectValue else {
            return status?["ready"]?.boolValue == true ? "Running" : "Unknown"
        }
        if state["running"] != nil { return "Running" }
        if let reason = state["waiting"]?["reason"]?.stringValue { return reason }
        if let reason = state["terminated"]?["reason"]?.stringValue { return reason }
        return "Unknown"
    }
}
