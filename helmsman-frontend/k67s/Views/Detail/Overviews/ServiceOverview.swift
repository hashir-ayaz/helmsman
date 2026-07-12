import SwiftUI

struct ServiceOverview: View {
    let object: JSONValue
    var ctx: String?
    var namespace: String?
    var onSelectPod: ((TablePayload.Row) -> Void)?
    var onShowAllPods: (() -> Void)?
    var onSelectEndpoints: ((TablePayload.Row) -> Void)?

    @State private var podsModel = RelatedPodsModel()
    @State private var endpointsModel = RelatedEndpointsModel()

    private static let maxDetailPods = 20

    private var serviceName: String {
        object["metadata"]?["name"]?.stringValue ?? ""
    }

    private var matchLabels: [String: JSONValue]? {
        K8s.podMatchLabels(from: object)
    }

    private var effectiveNamespace: String? {
        namespace ?? object["metadata"]?["namespace"]?.stringValue
    }

    private var isExternalName: Bool {
        object["spec"]?["type"]?.stringValue == "ExternalName"
    }

    private var podsTaskKey: String {
        let labels = matchLabels?.keys.sorted().joined(separator: ",") ?? ""
        return "\(ctx ?? "")|\(effectiveNamespace ?? "")|\(serviceName)|\(labels)"
    }

    private var endpointsTaskKey: String {
        "\(ctx ?? "")|\(effectiveNamespace ?? "")|\(serviceName)"
    }

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let type = object["spec"]?["type"]?.stringValue {
                    DetailRow(label: "Type", value: type)
                }
                if let ip = object["spec"]?["clusterIP"]?.stringValue {
                    DetailRow(label: "Cluster IP", value: ip)
                }
                if let externalName = object["spec"]?["externalName"]?.stringValue {
                    DetailRow(label: "External Name", value: externalName)
                }
                if let affinity = object["spec"]?["sessionAffinity"]?.stringValue {
                    DetailRow(label: "Affinity", value: affinity)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
            }
        }

        if let ports = object["spec"]?["ports"]?.arrayValue, !ports.isEmpty {
            DetailSection(title: "Ports") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(ports.enumerated()), id: \.offset) { _, p in
                        let port = p["port"]?.displayString ?? "?"
                        let target = p["targetPort"]?.displayString ?? port
                        let proto = p["protocol"]?.stringValue ?? "TCP"
                        let node = p["nodePort"]?.displayString
                        let value = "\(port) → \(target)/\(proto)" + (node.map { " (node \($0))" } ?? "")
                        DetailRow(label: p["name"]?.stringValue ?? proto, value: value)
                    }
                }
            }
        }

        if let selector = matchLabels, !selector.isEmpty {
            DetailSection(title: "Selector") { KeyValueChips(pairs: selector) }
        }

        if onSelectPod != nil {
            relatedPodsSection
        }

        if onSelectEndpoints != nil {
            relatedEndpointsSection
        }
    }

    @ViewBuilder private var relatedPodsSection: some View {
        DetailSection(title: "Pods") {
            Group {
                if isExternalName {
                    Text("ExternalName services have no pod selector.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if podsModel.isLoading {
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
                    Text("No pod selector — backends may be manual Endpoints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if podsModel.rows.isEmpty {
                    Text("No pods found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(podsModel.rows.prefix(Self.maxDetailPods))) { podRow in
                            RelatedPodRow(
                                name: podRow.object.name,
                                status: podsModel.leadingStatus(for: podRow),
                                summary: podsModel.trailingSummary(for: podRow)
                            ) {
                                onSelectPod?(podRow)
                            }
                            if podRow.id != podsModel.rows.prefix(Self.maxDetailPods).last?.id {
                                Divider()
                            }
                        }
                        if podsModel.rows.count > Self.maxDetailPods, let onShowAllPods {
                            Button("Show all \(podsModel.rows.count) in Pods list…", action: onShowAllPods)
                                .font(.caption)
                                .padding(.top, 6)
                        }
                    }
                }
            }
        }
        .task(id: podsTaskKey) {
            guard let onSelectPod,
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

    @ViewBuilder private var relatedEndpointsSection: some View {
        DetailSection(title: "Endpoints") {
            Group {
                if endpointsModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading endpoints…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = endpointsModel.error {
                    Text(error.errorDescription ?? "Failed to load endpoints")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if endpointsModel.addresses.isEmpty {
                    Text("No endpoints")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Ready \(endpointsModel.readyCount)")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Not ready \(endpointsModel.notReadyCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !endpointsModel.source.isEmpty {
                                Text(endpointsModel.source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(endpointsModel.addresses.prefix(24)) { entry in
                                Chip(
                                    text: entry.podName ?? entry.display,
                                    tint: entry.ready ? .blue : .orange
                                )
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        if let onSelectEndpoints, let ns = effectiveNamespace {
                            Button("Open Endpoints") {
                                onSelectEndpoints(
                                    .stub(name: serviceName, namespace: ns)
                                )
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .task(id: endpointsTaskKey) {
            guard let onSelectEndpoints,
                  let ctx,
                  let effectiveNamespace,
                  !effectiveNamespace.isEmpty,
                  !serviceName.isEmpty else {
                endpointsModel.reset()
                return
            }
            await endpointsModel.load(ctx: ctx, namespace: effectiveNamespace, serviceName: serviceName)
        }
    }
}
