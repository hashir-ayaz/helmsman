import SwiftUI

struct NodeOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let info = object["status"]?["nodeInfo"]?.objectValue {
                    if let v = info["kubeletVersion"]?.stringValue { DetailRow(label: "Kubelet", value: v) }
                    if let os = info["osImage"]?.stringValue { DetailRow(label: "OS Image", value: os) }
                    if let rt = info["containerRuntimeVersion"]?.stringValue { DetailRow(label: "Runtime", value: rt) }
                    if let arch = info["architecture"]?.stringValue { DetailRow(label: "Arch", value: arch) }
                }
                if let unschedulable = object["spec"]?["unschedulable"]?.boolValue {
                    DetailRow(label: "Unschedulable", value: unschedulable ? "Yes" : "No")
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
            }
        }

        if let addresses = object["status"]?["addresses"]?.arrayValue, !addresses.isEmpty {
            DetailSection(title: "Addresses") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(addresses.enumerated()), id: \.offset) { _, a in
                        DetailRow(label: a["type"]?.stringValue ?? "—",
                                  value: a["address"]?.stringValue ?? "—")
                    }
                }
            }
        }

        if let capacity = object["status"]?["capacity"]?.objectValue, !capacity.isEmpty {
            DetailSection(title: "Capacity") {
                FlowLayout(spacing: 4) {
                    ForEach(capacity.keys.sorted(), id: \.self) { key in
                        Chip(text: "\(key) \(capacity[key]?.displayString ?? "")", tint: .teal)
                    }
                }
            }
        }

        if let conditions = object["status"]?["conditions"]?.arrayValue, !conditions.isEmpty {
            DetailSection(title: "Conditions") { ConditionsList(conditions: conditions) }
        }
    }
}
