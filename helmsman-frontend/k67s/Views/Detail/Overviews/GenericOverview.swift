import SwiftUI

struct GenericOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let kind = object["kind"]?.stringValue {
                    DetailRow(label: "Kind", value: kind)
                }
                if let name = object["metadata"]?["name"]?.stringValue {
                    DetailRow(label: "Name", value: name)
                }
                if let ns = object["metadata"]?["namespace"]?.stringValue {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                if let phase = object["status"]?["phase"]?.stringValue {
                    DetailRow(label: "Status", value: phase,
                              valueColor: ResourceColors.statusColor(phase))
                }
                if let uid = object["metadata"]?["uid"]?.stringValue {
                    DetailRow(label: "UID", value: uid)
                }
            }
        }
    }
}
