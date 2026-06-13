import SwiftUI

struct ServiceOverview: View {
    let object: JSONValue

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

        if let selector = object["spec"]?["selector"]?.objectValue, !selector.isEmpty {
            DetailSection(title: "Selector") { KeyValueChips(pairs: selector) }
        }
    }
}
