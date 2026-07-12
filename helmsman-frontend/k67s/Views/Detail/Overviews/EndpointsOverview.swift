import SwiftUI

/// Detail overview for core/v1 Endpoints — lists every ready address×port
/// so Inspect is not limited by the table column's truncated "+N more" cell.
struct EndpointsOverview: View {
    let object: JSONValue

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
                DetailRow(label: "Addresses", value: "\(addressChips.count)", valueColor: .blue)
            }
        }

        if !addressChips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Addresses")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(addressChips.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.blue, in: Capsule())
                }

                FlowLayout(spacing: 6) {
                    ForEach(Array(addressChips.enumerated()), id: \.offset) { _, chip in
                        Chip(text: chip, tint: .blue)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Derived from subsets

    private var subsets: [JSONValue] {
        object["subsets"]?.arrayValue ?? []
    }

    private var readyCount: Int {
        subsets.reduce(0) { $0 + ($1["addresses"]?.arrayValue?.count ?? 0) }
    }

    private var notReadyCount: Int {
        subsets.reduce(0) { $0 + ($1["notReadyAddresses"]?.arrayValue?.count ?? 0) }
    }

    /// Every ready `ip:port` across subsets. If a subset has no ports, emit the IP alone.
    private var addressChips: [String] {
        var result: [String] = []
        for subset in subsets {
            let ips = (subset["addresses"]?.arrayValue ?? [])
                .compactMap { $0["ip"]?.stringValue }
            let ports = (subset["ports"]?.arrayValue ?? [])
                .compactMap { portNumber(from: $0) }

            if ports.isEmpty {
                result.append(contentsOf: ips)
            } else {
                for ip in ips {
                    for port in ports {
                        result.append("\(ip):\(port)")
                    }
                }
            }
        }
        return result
    }

    private func portNumber(from port: JSONValue) -> String? {
        guard let value = port["port"] else { return nil }
        switch value {
        case .int(let n): return String(n)
        case .double(let n): return String(Int(n))
        case .string(let s): return s
        default: return value.displayString.isEmpty ? nil : value.displayString
        }
    }
}
