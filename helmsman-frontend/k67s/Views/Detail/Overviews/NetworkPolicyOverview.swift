import SwiftUI

struct NetworkPolicyOverview: View {
    let object: JSONValue

    private var spec: JSONValue? { object["spec"] }
    private var podSelector: JSONValue? { spec?["podSelector"] }
    private var policyTypes: [String] { K8s.networkPolicyTypes(spec: spec) }
    private var ingressRules: [JSONValue] { spec?["ingress"]?.arrayValue ?? [] }
    private var egressRules: [JSONValue] { spec?["egress"]?.arrayValue ?? [] }

    private var hasPodSelectorContent: Bool {
        guard let podSelector else { return false }
        return !K8s.isEmptyLabelSelector(podSelector)
    }

    private var appliesToSummary: String {
        K8s.isEmptyLabelSelector(podSelector)
            ? "All pods in namespace"
            : K8s.labelSelectorSummary(podSelector, emptyLabel: "All pods in namespace")
    }

    private var deniesAllIngress: Bool {
        policyTypes.contains("Ingress") && ingressRules.isEmpty
    }

    private var deniesAllEgress: Bool {
        policyTypes.contains("Egress") && egressRules.isEmpty
    }

    private var allowsAllTraffic: Bool {
        policyTypes.isEmpty && ingressRules.isEmpty && egressRules.isEmpty
    }

    var body: some View {
        overviewSection

        if allowsAllTraffic {
            DetailSection(title: "Traffic") {
                Text("No isolation (allows all traffic)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        if hasPodSelectorContent {
            podSelectorSection
        }

        if deniesAllIngress {
            denyAllSection(title: "Ingress", message: "Denies all ingress")
        } else if !ingressRules.isEmpty {
            rulesSection(title: "Ingress Rules", rules: ingressRules, peerKey: "from")
        }

        if deniesAllEgress {
            denyAllSection(title: "Egress", message: "Denies all egress")
        } else if !egressRules.isEmpty {
            rulesSection(title: "Egress Rules", rules: egressRules, peerKey: "to")
        }
    }

    private var overviewSection: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let ns = object["metadata"]?["namespace"]?.stringValue {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                DetailRow(label: "Applies to", value: appliesToSummary)
                if !policyTypes.isEmpty {
                    DetailRow(label: "Policy types", value: policyTypes.joined(separator: ", "))
                }
                if policyTypes.contains("Ingress") || !ingressRules.isEmpty {
                    DetailRow(
                        label: "Ingress rules",
                        value: "\(ingressRules.count)",
                        valueColor: deniesAllIngress ? .orange : nil
                    )
                }
                if policyTypes.contains("Egress") || !egressRules.isEmpty {
                    DetailRow(
                        label: "Egress rules",
                        value: "\(egressRules.count)",
                        valueColor: deniesAllEgress ? .orange : nil
                    )
                }
            }
        }
    }

    private var podSelectorSection: some View {
        DetailSection(title: "Pod Selector") {
            VStack(alignment: .leading, spacing: 8) {
                if let labels = podSelector?["matchLabels"]?.objectValue, !labels.isEmpty {
                    KeyValueChips(pairs: labels)
                }
                ForEach(Array((podSelector?["matchExpressions"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, expr in
                    if let line = K8s.matchExpressionLabel(expr) {
                        DetailRow(label: "Expression", value: line)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func denyAllSection(title: String, message: String) -> some View {
        DetailSection(title: title) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func rulesSection(title: String, rules: [JSONValue], peerKey: String) -> some View {
        DetailSection(title: "\(title) (\(rules.count))") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    ruleBlock(rule, index: index + 1, peerKey: peerKey)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleBlock(_ rule: JSONValue, index: Int, peerKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rule \(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DetailRow(label: "Ports", value: portsSummary(rule["ports"]?.arrayValue))

            let peers = rule[peerKey]?.arrayValue ?? []
            if peers.isEmpty {
                DetailRow(label: peerKey == "from" ? "From" : "To", value: "Any")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(peerKey == "from" ? "From" : "To")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
                            ForEach(Array(K8s.networkPolicyPeerLines(peer).enumerated()), id: \.offset) { _, line in
                                Text("• \(line)")
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func portsSummary(_ ports: [JSONValue]?) -> String {
        guard let ports, !ports.isEmpty else { return "All ports" }
        return ports.map { K8s.networkPolicyPortLabel($0) }.joined(separator: ", ")
    }
}
