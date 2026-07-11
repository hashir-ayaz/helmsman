import SwiftUI

struct ServiceAccountOverview: View {
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
                DetailRow(label: "Automount", value: automountLabel)
                let secrets = secretsList
                DetailRow(label: "Secrets", value: secrets.isEmpty ? "—" : "\(secrets.count)")
            }
        }

        let secrets = secretsList
        if !secrets.isEmpty {
            DetailSection(title: "Secrets (\(secrets.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(secrets, id: \.self) { name in
                        Text(name)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }

        let imagePullSecrets = imagePullSecretsList
        if !imagePullSecrets.isEmpty {
            DetailSection(title: "Image Pull Secrets (\(imagePullSecrets.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(imagePullSecrets, id: \.self) { name in
                        Text(name)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var automountLabel: String {
        let token = object["spec"]?["automountServiceAccountToken"] ?? object["automountServiceAccountToken"]
        guard let token else { return "Yes" }
        return token.boolValue == true ? "Yes" : "No"
    }

    private var secretsList: [String] {
        (object["secrets"]?.arrayValue ?? [])
            .compactMap { $0["name"]?.stringValue }
    }

    private var imagePullSecretsList: [String] {
        (object["imagePullSecrets"]?.arrayValue ?? object["spec"]?["imagePullSecrets"]?.arrayValue ?? [])
            .compactMap { $0["name"]?.stringValue }
    }
}
