import SwiftUI

struct ClusterRoleBindingOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let name = object["metadata"]?["name"]?.stringValue {
                    DetailRow(label: "Name", value: name)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                let subjects = object["subjects"]?.arrayValue ?? []
                DetailRow(label: "Subjects", value: "\(subjects.count)")
            }
        }

        if let roleRef = object["roleRef"] {
            DetailSection(title: "Role Ref") {
                VStack(alignment: .leading, spacing: 4) {
                    if let kind = roleRef["kind"]?.stringValue,
                       let name = roleRef["name"]?.stringValue {
                        DetailRow(label: "Reference", value: "\(kind)/\(name)")
                    }
                    if let apiGroup = roleRef["apiGroup"]?.stringValue, !apiGroup.isEmpty {
                        DetailRow(label: "API Group", value: apiGroup)
                    }
                }
            }
        }

        let subjects = object["subjects"]?.arrayValue ?? []
        if !subjects.isEmpty {
            DetailSection(title: "Subjects (\(subjects.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(subjects.enumerated()), id: \.offset) { _, subject in
                        subjectRow(subject)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subjectRow(_ subject: JSONValue) -> some View {
        let kind = subject["kind"]?.stringValue ?? "—"
        let name = subject["name"]?.stringValue ?? "—"
        let namespace = subject["namespace"]?.stringValue

        VStack(alignment: .leading, spacing: 2) {
            Text("\(kind)/\(name)")
                .font(.callout)
                .textSelection(.enabled)
            if let namespace, !namespace.isEmpty {
                Text("namespace: \(namespace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
