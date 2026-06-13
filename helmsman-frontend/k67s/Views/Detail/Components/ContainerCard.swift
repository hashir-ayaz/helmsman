import SwiftUI

/// One container's detail: status, image, ports, resources, restarts, env count.
struct ContainerCard: View {
    let pair: K8s.ContainerPair

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let image = pair.spec["image"]?.stringValue {
                Text(image)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            meta
            ports
            resources
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let ready = pair.status?["ready"]?.boolValue {
                StatusDot(status: ready ? "ready" : "pending")
            }
            Text(pair.name).font(.callout).fontWeight(.medium)
            Spacer(minLength: 0)
            let state = K8s.containerStateLabel(pair.status)
            Chip(text: state, tint: ResourceColors.statusColor(state))
        }
    }

    @ViewBuilder private var meta: some View {
        HStack(spacing: 12) {
            if let restarts = pair.status?["restartCount"]?.intValue {
                Label("\(restarts) restarts", systemImage: "arrow.clockwise")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let env = pair.spec["env"]?.arrayValue, !env.isEmpty {
                Label("\(env.count) env", systemImage: "list.bullet")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var ports: some View {
        if let ports = pair.spec["ports"]?.arrayValue, !ports.isEmpty {
            let portString = ports.compactMap { p -> String? in
                guard let n = p["containerPort"]?.intValue else { return nil }
                return "\(n)/\(p["protocol"]?.stringValue ?? "TCP")"
            }.joined(separator: ",")
            if !portString.isEmpty { PortChipsView(value: portString) }
        }
    }

    @ViewBuilder private var resources: some View {
        let requests = pair.spec["resources"]?["requests"]?.objectValue
        let limits = pair.spec["resources"]?["limits"]?.objectValue
        if (requests?.isEmpty == false) || (limits?.isEmpty == false) {
            HStack(alignment: .top, spacing: 16) {
                if let requests, !requests.isEmpty { quantityColumn("Requests", requests) }
                if let limits, !limits.isEmpty { quantityColumn("Limits", limits) }
            }
        }
    }

    private func quantityColumn(_ title: String, _ quantities: [String: JSONValue]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(quantities.keys.sorted(), id: \.self) { key in
                    Chip(text: "\(key) \(quantities[key]?.displayString ?? "")", tint: .green)
                }
            }
        }
    }
}
