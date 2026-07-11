import SwiftUI

struct PodOverview: View {
    let object: JSONValue
    var events: [ResourceDetailModel.PodRelatedEvent] = []
    var isLoadingEvents = false

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let phase = object["status"]?["phase"]?.stringValue {
                    DetailRow(label: "Phase", value: phase,
                              valueColor: ResourceColors.statusColor(phase))
                }
                if let ready = K8s.podReady(object) {
                    DetailRow(label: "Ready", value: ready)
                }
                let restarts = K8s.podRestarts(object)
                DetailRow(
                    label: "Restarts",
                    value: "\(restarts)",
                    valueColor: restarts > 0 ? .orange : nil
                )
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                if let qos = object["status"]?["qosClass"]?.stringValue {
                    DetailRow(label: "QoS", value: qos)
                }
                if let node = object["spec"]?["nodeName"]?.stringValue {
                    DetailRow(label: "Node", value: node)
                }
                if let ip = object["status"]?["podIP"]?.stringValue {
                    DetailRow(label: "Pod IP", value: ip)
                }
                if let sa = object["spec"]?["serviceAccountName"]?.stringValue {
                    DetailRow(label: "Service Acct", value: sa)
                }
                if let owner = K8s.controlledBy(object) {
                    DetailRow(label: "Controlled By", value: owner)
                }
            }
        }

        if let conditions = object["status"]?["conditions"]?.arrayValue, !conditions.isEmpty {
            DetailSection(title: "Conditions") { ConditionsList(conditions: conditions) }
        }

        let containers = K8s.containerPairs(object)
        if !containers.isEmpty {
            let title = K8s.podReady(object).map { "Containers (\($0))" } ?? "Containers (\(containers.count))"
            DetailSection(title: title) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(containers) { ContainerCard(pair: $0) }
                }
            }
        }

        let initContainers = K8s.initContainerPairs(object)
        if !initContainers.isEmpty {
            DetailSection(title: "Init Containers (\(initContainers.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(initContainers) { ContainerCard(pair: $0) }
                }
            }
        }

        if let volumes = object["spec"]?["volumes"]?.arrayValue, !volumes.isEmpty {
            DetailSection(title: "Volumes (\(volumes.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(volumes.enumerated()), id: \.offset) { _, volume in
                        Text(volume["name"]?.stringValue ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let tolerations = object["spec"]?["tolerations"]?.arrayValue, !tolerations.isEmpty {
            DetailSection(title: "Scheduling") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tolerations.enumerated()), id: \.offset) { _, t in
                        let parts = [t["key"]?.stringValue, t["effect"]?.stringValue].compactMap { $0 }
                        Text(parts.joined(separator: ": "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        eventsSection
    }

    @ViewBuilder
    private var eventsSection: some View {
        DetailSection(title: "Events") {
            if isLoadingEvents {
                PodEventsSkeleton()
            } else if events.isEmpty {
                Text("No events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { PodEventRowView(event: $0) }
                }
            }
        }
    }
}
