import SwiftUI

struct WorkloadOverview: View {
    let object: JSONValue
    var ctx: String?
    var namespace: String?
    var onSelectPod: ((TablePayload.Row) -> Void)?

    @State private var podsModel = RelatedPodsModel()

    private var matchLabels: [String: JSONValue]? {
        object["spec"]?["selector"]?["matchLabels"]?.objectValue
    }

    private var podsTaskKey: String {
        let labels = matchLabels?.keys.sorted().joined(separator: ",") ?? ""
        return "\(ctx ?? "")|\(effectiveNamespace ?? "")|\(labels)"
    }

    private var effectiveNamespace: String? {
        namespace ?? object["metadata"]?["namespace"]?.stringValue
    }

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

        if let selector = matchLabels, !selector.isEmpty {
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

        if onSelectPod != nil {
            relatedPodsSection
        }

        if let conditions = object["status"]?["conditions"]?.arrayValue, !conditions.isEmpty {
            DetailSection(title: "Conditions") { ConditionsList(conditions: conditions) }
        }
    }

    @ViewBuilder private var relatedPodsSection: some View {
        DetailSection(title: "Pods") {
            Group {
                if podsModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading pods…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = podsModel.error {
                    Text(error.errorDescription ?? "Failed to load pods")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if matchLabels?.isEmpty != false {
                    Text("No selector")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if podsModel.rows.isEmpty {
                    Text("No pods found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(podsModel.rows) { podRow in
                            RelatedPodRow(
                                name: podRow.object.name,
                                status: podsModel.leadingStatus(for: podRow),
                                summary: podsModel.trailingSummary(for: podRow)
                            ) {
                                onSelectPod?(podRow)
                            }
                            if podRow.id != podsModel.rows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .task(id: podsTaskKey) {
            guard onSelectPod != nil,
                  let ctx,
                  let effectiveNamespace,
                  !effectiveNamespace.isEmpty,
                  let matchLabels,
                  !matchLabels.isEmpty else {
                podsModel.reset()
                return
            }
            await podsModel.load(ctx: ctx, namespace: effectiveNamespace, matchLabels: matchLabels)
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
