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

    /// RFC3339 timestamp for display (pass-through when already formatted).
    static func formatTimestamp(_ timestamp: String?) -> String? {
        guard let timestamp, !timestamp.isEmpty else { return nil }
        return timestamp
    }

    /// Human-readable timestamp like "11-Jul-2026 at 8:50:04 PM".
    /// Falls back to the raw string when parsing fails.
    static func displayTimestamp(_ timestamp: String?) -> String? {
        guard let timestamp, !timestamp.isEmpty else { return nil }
        guard let date = iso8601.date(from: timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy 'at' h:mm:ss a"
        return formatter.string(from: date)
    }

    /// Event source as "component" or "component on host".
    static func eventSourceLabel(_ object: JSONValue) -> String? {
        let component = object["source"]?["component"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = object["source"]?["host"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch (component?.isEmpty == false ? component : nil,
                host?.isEmpty == false ? host : nil) {
        case let (c?, h?): return "\(c) on \(h)"
        case let (c?, nil): return c
        case let (nil, h?): return h
        default: return nil
        }
    }

    /// Best-effort First Seen for an Event object.
    static func eventFirstSeen(_ object: JSONValue) -> String? {
        displayTimestamp(
            nonEmpty(object["firstTimestamp"]?.stringValue)
                ?? nonEmpty(object["eventTime"]?.stringValue)
                ?? nonEmpty(object["metadata"]?["creationTimestamp"]?.stringValue)
        )
    }

    /// Best-effort Last Seen for an Event object.
    static func eventLastSeen(_ object: JSONValue) -> String? {
        displayTimestamp(
            nonEmpty(object["lastTimestamp"]?.stringValue)
                ?? nonEmpty(object["series"]?["lastObservedTime"]?.stringValue)
                ?? nonEmpty(object["eventTime"]?.stringValue)
                ?? nonEmpty(object["firstTimestamp"]?.stringValue)
                ?? nonEmpty(object["metadata"]?["creationTimestamp"]?.stringValue)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    /// Kubernetes label selector string from `matchLabels`, e.g. `app=nginx,version=v1`.
    static func labelSelector(from matchLabels: [String: JSONValue]) -> String {
        matchLabels.keys.sorted().map { key in
            "\(key)=\(matchLabels[key]?.displayString ?? "")"
        }.joined(separator: ",")
    }

    /// Pod selector labels for workloads (`spec.selector.matchLabels`) or Services (`spec.selector`).
    static func podMatchLabels(from object: JSONValue) -> [String: JSONValue]? {
        if let matchLabels = object["spec"]?["selector"]?["matchLabels"]?.objectValue,
           !matchLabels.isEmpty {
            return matchLabels
        }
        if object["kind"]?.stringValue == "Service",
           let selector = object["spec"]?["selector"]?.objectValue,
           !selector.isEmpty {
            return selector
        }
        return nil
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

    /// Parsed container state for display.
    struct ContainerStateDetail {
        let phase: String
        let reason: String?
        let message: String?
        let startedAt: String?
        let finishedAt: String?
        let exitCode: Int?

        var chipLabel: String {
            if phase == "Running" { return "Running" }
            if let reason, !reason.isEmpty { return reason }
            return phase
        }

        var lastStateSummary: String? {
            guard phase != "Running" else { return nil }
            var parts = [phase]
            if let reason, !reason.isEmpty { parts.append(reason) }
            if let exitCode { parts.append("exit \(exitCode)") }
            return parts.joined(separator: ": ")
        }
    }

    /// Joins spec.containers[] with status.containerStatuses[] by name.
    static func containerPairs(_ object: JSONValue) -> [ContainerPair] {
        pairContainers(
            spec: object["spec"]?["containers"]?.arrayValue,
            statuses: object["status"]?["containerStatuses"]?.arrayValue
        )
    }

    /// Joins spec.initContainers[] with status.initContainerStatuses[] by name.
    static func initContainerPairs(_ object: JSONValue) -> [ContainerPair] {
        pairContainers(
            spec: object["spec"]?["initContainers"]?.arrayValue,
            statuses: object["status"]?["initContainerStatuses"]?.arrayValue
        )
    }

    private static func pairContainers(spec: [JSONValue]?, statuses: [JSONValue]?) -> [ContainerPair] {
        guard let spec else { return [] }
        var byName: [String: JSONValue] = [:]
        for st in statuses ?? [] {
            if let n = st["name"]?.stringValue { byName[n] = st }
        }
        return spec.compactMap { container in
            guard let name = container["name"]?.stringValue else { return nil }
            return ContainerPair(name: name, spec: container, status: byName[name])
        }
    }

    /// Human label for a container's runtime state.
    static func containerStateLabel(_ status: JSONValue?) -> String {
        containerStateDetail(status?["state"])?.chipLabel
            ?? (status?["ready"]?.boolValue == true ? "Running" : "Unknown")
    }

    /// Extracts running / waiting / terminated details from a state object.
    static func containerStateDetail(_ state: JSONValue?) -> ContainerStateDetail? {
        guard let state = state?.objectValue else { return nil }
        if let running = state["running"]?.objectValue {
            return ContainerStateDetail(
                phase: "Running",
                reason: nil,
                message: nil,
                startedAt: running["startedAt"]?.stringValue,
                finishedAt: nil,
                exitCode: nil
            )
        }
        if let waiting = state["waiting"]?.objectValue {
            return ContainerStateDetail(
                phase: "Waiting",
                reason: waiting["reason"]?.stringValue,
                message: waiting["message"]?.stringValue,
                startedAt: nil,
                finishedAt: nil,
                exitCode: nil
            )
        }
        if let terminated = state["terminated"]?.objectValue {
            return ContainerStateDetail(
                phase: "Terminated",
                reason: terminated["reason"]?.stringValue,
                message: terminated["message"]?.stringValue,
                startedAt: terminated["startedAt"]?.stringValue,
                finishedAt: terminated["finishedAt"]?.stringValue,
                exitCode: terminated["exitCode"]?.intValue
            )
        }
        return nil
    }
}
