import SwiftUI

/// One container's detail: status, image, ports, resources, restarts, env count.
struct ContainerCard: View {
    let pair: K8s.ContainerPair

    private var state: K8s.ContainerStateDetail? {
        K8s.containerStateDetail(pair.status?["state"])
    }

    private var lastState: K8s.ContainerStateDetail? {
        K8s.containerStateDetail(pair.status?["lastState"])
    }

    private var isReady: Bool {
        pair.status?["ready"]?.boolValue == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            imageBlock
            statusBadges
            timestamps
            reasonCallout
            lastStateBlock
            ports
            resources
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 6) {
            StatusDot(status: isReady ? "ready" : "pending")
            Text(pair.name)
                .font(.callout)
                .fontWeight(.medium)
            Spacer(minLength: 0)
            let label = K8s.containerStateLabel(pair.status)
            Chip(text: label, tint: ResourceColors.statusColor(label))
        }
    }

    @ViewBuilder
    private var imageBlock: some View {
        if let image = pair.spec["image"]?.stringValue {
            VStack(alignment: .leading, spacing: 4) {
                Text("Image")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(image)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.teal)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        FlowLayout(spacing: 6) {
            Chip(
                text: isReady ? "Ready" : "Not Ready",
                tint: isReady ? .green : .red
            )
            if let restarts = pair.status?["restartCount"]?.intValue {
                Chip(
                    text: "\(restarts) restarts",
                    tint: restarts > 0 ? .orange : .secondary
                )
            }
            if let exitCode = state?.exitCode {
                Chip(text: "exit \(exitCode)", tint: .red)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var timestamps: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let started = K8s.formatTimestamp(state?.startedAt) {
                Text("Started: \(started)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let finished = K8s.formatTimestamp(state?.finishedAt) {
                Text("Finished: \(finished)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var reasonCallout: some View {
        if let reason = state?.reason, !reason.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reason")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                if let message = state?.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var lastStateBlock: some View {
        if let lastState, lastState.phase != "Running" {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last State:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = lastState.lastStateSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if let started = K8s.formatTimestamp(lastState.startedAt) {
                    Text("Started: \(started)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let finished = K8s.formatTimestamp(lastState.finishedAt) {
                    Text("Finished: \(finished)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var ports: some View {
        if let ports = pair.spec["ports"]?.arrayValue, !ports.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ports")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let portString = ports.compactMap { p -> String? in
                    guard let n = p["containerPort"]?.intValue else { return nil }
                    return "\(n)/\(p["protocol"]?.stringValue ?? "TCP")"
                }.joined(separator: ",")
                if !portString.isEmpty { PortChipsView(value: portString) }
            }
        }
    }

    @ViewBuilder
    private var resources: some View {
        let requests = pair.spec["resources"]?["requests"]?.objectValue
        let limits = pair.spec["resources"]?["limits"]?.objectValue
        if (requests?.isEmpty == false) || (limits?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resources")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    if let requests, !requests.isEmpty { quantityColumn("Requests", requests) }
                    if let limits, !limits.isEmpty { quantityColumn("Limits", limits) }
                }
            }
        }
    }

    private func quantityColumn(_ title: String, _ quantities: [String: JSONValue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(quantities.keys.sorted(), id: \.self) { key in
                    Chip(
                        text: "\(key) \(quantities[key]?.displayString ?? "")",
                        tint: resourceTint(for: key)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private func resourceTint(for key: String) -> Color {
        switch key.lowercased() {
        case "cpu": return .blue
        case "memory": return .green
        default: return .secondary
        }
    }
}
