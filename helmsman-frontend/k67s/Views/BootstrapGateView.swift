import SwiftUI
import AppKit

/// Branded full-window gate shown while Helmsman boots and connects to the cluster.
struct BootstrapGateView: View {
    enum Phase: Equatable {
        case connecting(step: AppModel.BootstrapStep)
        case failed(title: String, message: String, code: String?)
    }

    let phase: Phase
    var onRetry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.6),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .connecting(let step):
            connectingContent(step: step)
        case .failed(let title, let message, let code):
            failedContent(title: title, message: message, code: code)
        }
    }

    private func connectingContent(step: AppModel.BootstrapStep) -> some View {
        VStack(spacing: 24) {
            appIcon
            VStack(spacing: 8) {
                Text("Helmsman")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(stepMessage(step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : HelmsmanMotion.soft, value: step)
            }
            ProgressView()
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(32)
    }

    private func failedContent(title: String, message: String, code: String?) -> some View {
        VStack(spacing: 20) {
            appIcon
            VStack(spacing: 8) {
                Text("Helmsman")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.title3.weight(.medium))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let tip = failureTip(for: code) {
                Text(tip)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            if let onRetry {
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(32)
    }

    private var appIcon: some View {
        Group {
            if let image = NSApplication.shared.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "helm")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: 72, height: 72)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private func stepMessage(_ step: AppModel.BootstrapStep) -> String {
        switch step {
        case .checkingNetwork:
            "Checking network connection…"
        case .startingBackend:
            "Starting local backend…"
        case .checkingCluster:
            "Reading kubeconfig…"
        case .loadingContexts:
            "Loading contexts…"
        }
    }

    private func failureTip(for code: String?) -> String? {
        switch code {
        case "no_network":
            "Turn Wi‑Fi back on or plug in Ethernet, then tap Retry."
        case "kubeconfig_not_found":
            "Point KUBECONFIG at your config file, or place one at ~/.kube/config."
        case "kubeconfig_invalid":
            "Check that your kubeconfig is valid YAML and contains at least one context."
        case "no_contexts":
            "Add a cluster context to your kubeconfig, then try again."
        case "backend_unreachable":
            "If you're developing locally, run make run in helmsman-api and try again."
        default:
            nil
        }
    }
}
