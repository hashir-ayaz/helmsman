import SwiftUI

struct ConfigOverview: View {
    let object: JSONValue

    var body: some View {
        let isSecret = object["kind"]?.stringValue == "Secret"
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if isSecret, let type = object["type"]?.stringValue {
                    DetailRow(label: "Type", value: type)
                }
                let dataKeys = object["data"]?.objectValue?.count ?? 0
                let binaryKeys = object["binaryData"]?.objectValue?.count ?? 0
                DetailRow(label: "Keys", value: "\(dataKeys + binaryKeys)")
                if let immutable = object["immutable"]?.boolValue {
                    DetailRow(label: "Immutable", value: immutable ? "Yes" : "No")
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
            }
        }

        if let keys = object["data"]?.objectValue?.keys, !keys.isEmpty {
            DetailSection(title: isSecret ? "Keys (values hidden)" : "Keys") {
                FlowLayout(spacing: 4) {
                    ForEach(keys.sorted(), id: \.self) { Chip(text: $0, tint: .purple) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
