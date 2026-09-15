import SwiftUI

/// Context + namespace scope controls as rounded pill menus in the detail toolbar.
/// The context menu also links to the full-window cluster picker.
struct ScopePickerPills: View {
    @Bindable var app: AppModel
    @State private var isSwitching = false

    var body: some View {
        HStack(spacing: 8) {
            contextMenu
            namespaceMenu
        }
        .toolbarChromeInset()
        .onChange(of: app.selectedNamespace) { _, _ in
            Task { await app.reloadSidebarCounts() }
        }
    }

    private var contextMenu: some View {
        Menu {
            ForEach(app.contexts) { context in
                Button {
                    switchContext(to: context.name)
                } label: {
                    if app.selectedContext == context.name {
                        Label(context.name, systemImage: "checkmark")
                    } else {
                        Text(context.name)
                    }
                }
            }
            Divider()
            Button("Choose a Cluster…", systemImage: "square.grid.2x2") {
                app.showContextPicker()
            }
        } label: {
            pillLabel(icon: "helm", title: app.contextDisplayName, isBusy: isSwitching)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .help("Kubernetes context")
    }

    /// Connects in place. On failure the picker opens so the failed card can
    /// show the message and next step, with the other clusters one click away.
    private func switchContext(to name: String) {
        guard name != app.selectedContext, !isSwitching else { return }
        isSwitching = true
        Task {
            defer { isSwitching = false }
            if await app.connect(to: name) != nil {
                app.showContextPicker()
            }
        }
    }

    private var namespaceMenu: some View {
        Menu {
            ForEach(app.namespacePickerOptions, id: \.self) { namespace in
                Button {
                    app.selectedNamespace = namespace
                } label: {
                    if app.selectedNamespace == namespace {
                        Label(namespace, systemImage: "checkmark")
                    } else {
                        Text(namespace)
                    }
                }
            }
        } label: {
            pillLabel(icon: "square.3.layers.3d", title: app.selectedNamespace)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Namespace scope")
    }

    private func pillLabel(icon: String, title: String, isBusy: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 180, alignment: .leading)
        .background(.quaternary, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
    }
}

private struct ScopePickerToolbarModifier: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigation) {
                ScopePickerPills(app: app)
            }
        }
    }
}

extension View {
    /// Breathing room inside the macOS toolbar chrome border.
    func toolbarChromeInset() -> some View {
        padding(.horizontal, 6).padding(.vertical, 5)
    }

    func scopePickerToolbar(app: AppModel) -> some View {
        modifier(ScopePickerToolbarModifier(app: app))
    }
}
