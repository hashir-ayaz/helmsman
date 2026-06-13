import SwiftUI

struct WorkloadOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                replicaRows
                if let strategy = object["spec"]?["strategy"]?["type"]?.stringValue
                    ?? object["spec"]?["updateStrategy"]?["type"]?.stringValue {
                    DetailRow(label: "Strategy", value: strategy)
                }
                if let paused = object["spec"]?["paused"]?.boolValue {
                    DetailRow(label: "Paused", value: paused ? "Yes" : "No")
                }
                if let service = object["spec"]?["serviceName"]?.stringValue {
                    DetailRow(label: "Service", value: service)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                if let owner = K8s.controlledBy(object) {
                    DetailRow(label: "Controlled By", value: owner)
                }
            }
        }

        if let selector = object["spec"]?["selector"]?["matchLabels"]?.objectValue, !selector.isEmpty {
            DetailSection(title: "Selector") { KeyValueChips(pairs: selector) }
        }

        if let images = templateImages, !images.isEmpty {
            DetailSection(title: "Images") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(images, id: \.self) { image in
                        Text(image)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }

        if let conditions = object["status"]?["conditions"]?.arrayValue, !conditions.isEmpty {
            DetailSection(title: "Conditions") { ConditionsList(conditions: conditions) }
        }
    }

    @ViewBuilder private var replicaRows: some View {
        if object["kind"]?.stringValue == "DaemonSet" {
            DetailRow(label: "Desired", value: object["status"]?["desiredNumberScheduled"]?.displayString ?? "0")
            DetailRow(label: "Ready", value: object["status"]?["numberReady"]?.displayString ?? "0")
            DetailRow(label: "Available", value: object["status"]?["numberAvailable"]?.displayString ?? "0")
            DetailRow(label: "Updated", value: object["status"]?["updatedNumberScheduled"]?.displayString ?? "0")
        } else {
            if let desired = object["spec"]?["replicas"]?.displayString {
                DetailRow(label: "Desired", value: desired)
            }
            DetailRow(label: "Ready", value: object["status"]?["readyReplicas"]?.displayString ?? "0")
            DetailRow(label: "Available", value: object["status"]?["availableReplicas"]?.displayString ?? "0")
            DetailRow(label: "Updated", value: object["status"]?["updatedReplicas"]?.displayString ?? "0")
        }
    }

    private var templateImages: [String]? {
        object["spec"]?["template"]?["spec"]?["containers"]?.arrayValue?
            .compactMap { $0["image"]?.stringValue }
    }
}
