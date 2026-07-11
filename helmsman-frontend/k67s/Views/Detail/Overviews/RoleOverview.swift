import SwiftUI

struct RoleOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let name = object["metadata"]?["name"]?.stringValue {
                    DetailRow(label: "Name", value: name)
                }
                if let ns = object["metadata"]?["namespace"]?.stringValue {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                let rules = object["rules"]?.arrayValue ?? []
                DetailRow(label: "Rules", value: "\(rules.count)")
            }
        }

        let rules = object["rules"]?.arrayValue ?? []
        if !rules.isEmpty {
            DetailSection(title: "Rules (\(rules.count))") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        ruleBlock(rule, index: index + 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ruleBlock(_ rule: JSONValue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rule \(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let verbs = stringList(rule["verbs"]?.arrayValue) {
                DetailRow(label: "Verbs", value: verbs)
            }
            if let apiGroups = stringList(rule["apiGroups"]?.arrayValue) {
                DetailRow(label: "API Groups", value: apiGroups)
            }
            if let resources = stringList(rule["resources"]?.arrayValue) {
                DetailRow(label: "Resources", value: resources)
            }
            if let resourceNames = stringList(rule["resourceNames"]?.arrayValue) {
                DetailRow(label: "Resource Names", value: resourceNames)
            }
            if let nonResourceURLs = stringList(rule["nonResourceURLs"]?.arrayValue) {
                DetailRow(label: "Non-Resource URLs", value: nonResourceURLs)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stringList(_ values: [JSONValue]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        let parts = values.compactMap(\.stringValue)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
