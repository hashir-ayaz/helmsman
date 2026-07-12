import SwiftUI

/// Detail overview for core/v1 Endpoints — lists every ready address×port
/// so Inspect is not limited by the table column's truncated "+N more" cell.
struct EndpointsOverview: View {
    let object: JSONValue
    var namespace: String?
    var onSelectPod: ((TablePayload.Row) -> Void)?

    private var entries: [EndpointAddressEntry] {
        EndpointAddressParser.fromEndpoints(object)
    }

    var body: some View {
        DetailSection(title: "Metadata") {
            VStack(alignment: .leading, spacing: 4) {
                if let ns = object["metadata"]?["namespace"]?.stringValue {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                DetailRow(label: "Ready", value: "\(readyCount)", valueColor: .green)
                DetailRow(label: "Not Ready", value: "\(notReadyCount)")
                DetailRow(label: "Addresses", value: "\(entries.count)", valueColor: .blue)
            }
        }

        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Addresses")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(entries.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.blue, in: Capsule())
                }

                FlowLayout(spacing: 6) {
                    ForEach(entries) { entry in
                        if let podName = entry.podName, let onSelectPod, let ns = namespace {
                            Button {
                                onSelectPod(.stub(name: podName, namespace: ns))
                            } label: {
                                Chip(text: podName, tint: entry.ready ? .blue : .orange)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Chip(text: entry.display, tint: entry.ready ? .blue : .orange)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readyCount: Int {
        entries.filter(\.ready).count
    }

    private var notReadyCount: Int {
        entries.filter { !$0.ready }.count
    }
}
