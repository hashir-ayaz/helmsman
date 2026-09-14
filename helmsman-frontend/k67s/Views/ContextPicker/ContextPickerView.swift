import SwiftUI

/// Full-window cluster chooser shown while `connectionPhase == .selectingContext`.
/// Probes every kubeconfig context in parallel and connects on card click.
struct ContextPickerView: View {
    @Bindable var app: AppModel
    @State private var picker = ContextPickerModel()
    @State private var refreshToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HelmsmanGateBackground()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if app.contexts.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        // Back/Refresh must not race an in-flight connect.
        .disabled(picker.connectingContext != nil)
        .task(id: refreshToken) {
            await picker.probeAll(app.contexts)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            HelmsmanAppIcon(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a cluster")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.hasConnectedContext && picker.connectingContext == nil {
                Button("Back to \(app.contextDisplayName)", systemImage: "chevron.left") {
                    app.returnToCluster()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .lineLimit(1)
                .truncationMode(.middle)
                // Trailing alignment keeps the button hugging Refresh when the
                // label is shorter than the cap; the slack merges into the Spacer.
                .frame(maxWidth: 260, alignment: .trailing)
            }
            Button("Refresh", systemImage: "arrow.clockwise") {
                refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("r")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private var subtitle: String {
        let count = app.contexts.count
        let noun = count == 1 ? "context" : "contexts"
        return "Helmsman found \(count) \(noun) in your kubeconfig. Pick one to connect."
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(app.contexts) { context in
                    ContextCardView(
                        context: context,
                        health: picker.health[context.name],
                        isConnecting: picker.connectingContext == context.name,
                        isActive: app.hasConnectedContext && context.name == app.selectedContext
                    ) {
                        Task { await picker.connect(context, app: app) }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .animation(reduceMotion ? nil : HelmsmanMotion.soft, value: picker.health)
        }
    }

    // MARK: - Empty state

    /// Defensive only — the backend answers 503 `no_contexts` before this shows.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contexts Found", systemImage: "helm")
        } description: {
            Text("Your kubeconfig has no contexts. Add one with kubectl config set-context, then press Refresh.")
        } actions: {
            Button("Refresh") { refresh() }
                .buttonStyle(.borderedProminent)
                .tint(HelmsmanBrand.amber)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Reloads the kubeconfig contexts, then re-probes. A failed reload moves
    /// the phase to `.failed`, so the gate takes over with Retry.
    private func refresh() {
        Task {
            guard await app.loadContexts() else { return }
            refreshToken += 1
        }
    }
}
