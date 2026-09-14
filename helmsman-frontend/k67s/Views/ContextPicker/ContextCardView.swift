import SwiftUI
import AppKit

/// One kubeconfig context in the picker grid. The whole card is the button;
/// health, badges and any probe failure render inline.
struct ContextCardView: View {
    let context: ContextInfo
    let health: ContextHealth?      // nil = not probed yet
    let isConnecting: Bool
    let isActive: Bool              // the context the app is currently connected to
    let onSelect: () -> Void
    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        Button(action: onSelect) {
            cardBody
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Connect to \(context.name)")
        .accessibilityHint("Status: \(healthLabel)")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            VStack(alignment: .leading, spacing: 6) {
                detailRow(label: "Cluster", value: context.cluster)
                detailRow(label: "Namespace", value: context.namespace.isEmpty ? "default" : context.namespace)
            }
            badgesRow
            statusPanel
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: shape)
        .overlay(shape.strokeBorder(strokeColor, lineWidth: isActive ? 1.5 : 1))
        .overlay {
            if isConnecting {
                shape.fill(.background.opacity(0.6))
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(.callout)
                }
            }
        }
        .opacity(isConnecting ? 0.9 : 1)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "helm")
                .font(.title3)
                .foregroundStyle(HelmsmanBrand.amber)
            Text(context.name)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            healthBadge
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Fixed height so cards without badges match cards with them.
    private var badgesRow: some View {
        HStack(spacing: 6) {
            if context.isCurrent {
                badge("kubeconfig current", tint: .secondary)
            }
            if isActive {
                badge("Connected", tint: HelmsmanBrand.amber)
            }
        }
        .frame(height: 20, alignment: .leading)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    /// Bottom panel present on every card: a title line plus four reserved
    /// caption lines, so healthy and failed cards share one height. Failed cards
    /// show the next-step tip here; the full text is also available as a tooltip.
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(statusTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(statusBody)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4, reservesSpace: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(statusBody)
    }

    private var statusTitle: String {
        switch health {
        case nil: "Not checked yet"
        case .probing: "Checking reachability…"
        case .reachable: "Ready to connect"
        case .unreachable(let error): Self.title(for: error)
        }
    }

    private var statusBody: String {
        switch health {
        case nil, .reachable: "Click to open this cluster."
        case .probing: "Dialing the API server…"
        case .unreachable(let error):
            Self.tip(for: error) ?? error.errorDescription ?? "Something went wrong."
        }
    }

    // MARK: - Health

    private var healthBadge: some View {
        HStack(spacing: 6) {
            if case .probing = health {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
            }
            Text(healthLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var healthLabel: String {
        switch health {
        case nil: "Unknown"
        case .probing: "Checking…"
        case .reachable: "Reachable"
        case .unreachable(let error): Self.failureLabel(for: error)
        }
    }

    private var healthColor: Color {
        switch health {
        case nil, .probing: .gray
        case .reachable: HelmsmanBrand.success
        case .unreachable(let error):
            error.code == "cluster_auth" ? HelmsmanBrand.danger : HelmsmanBrand.warning
        }
    }

    private var strokeColor: Color {
        if isActive { return HelmsmanBrand.amber }
        if isHovered { return .primary.opacity(0.18) }
        return Color(nsColor: .separatorColor)
    }

    private static func failureLabel(for error: APIError) -> String {
        if case .notFound = error { return "Not in kubeconfig" }
        switch error.code {
        case "cluster_timeout": return "Timed out"
        case "cluster_auth": return "Auth failed"
        default: return "Unreachable"
        }
    }

    /// A 404 (`context_not_found`) arrives as `.notFound` with no typed code,
    /// so `displayTitle` falls back to "Couldn’t Load"; name it properly here.
    private static func title(for error: APIError) -> String {
        if case .notFound = error { return "Context Not Found" }
        return error.displayTitle
    }

    private static func tip(for error: APIError) -> String? {
        if case .notFound = error { return "Press Refresh to reload your contexts." }
        return error.displayTip
    }
}

#Preview {
    let contexts = [
        ContextInfo(name: "kind-helmsman", cluster: "kind-helmsman", namespace: "", isCurrent: true),
        ContextInfo(name: "docker-desktop", cluster: "docker-desktop", namespace: "kube-system", isCurrent: false),
        ContextInfo(
            name: "arn:aws:eks:us-east-1:123456789012:cluster/prod",
            cluster: "arn:aws:eks:us-east-1:123456789012:cluster/prod",
            namespace: "payments",
            isCurrent: false
        ),
    ]
    VStack(spacing: 16) {
        ContextCardView(context: contexts[0], health: .reachable, isConnecting: false, isActive: true) {}
        ContextCardView(context: contexts[1], health: .probing, isConnecting: false, isActive: false) {}
        ContextCardView(
            context: contexts[2],
            health: .unreachable(.unavailable(
                code: "cluster_auth",
                message: "Unable to connect to the server: getting credentials: exec: executable aws not found"
            )),
            isConnecting: false,
            isActive: false
        ) {}
    }
    .padding(24)
    .frame(width: 380)
}
