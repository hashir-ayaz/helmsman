import SwiftUI

/// Context + namespace scope controls as rounded pill menus in the detail toolbar.
struct ScopePickerPills: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: 8) {
            contextMenu
            namespaceMenu
        }
        .onChange(of: app.selectedContext) { _, _ in
            Task {
                await app.contextDidChange()
                await app.reloadSidebarCounts()
            }
        }
        .onChange(of: app.selectedNamespace) { _, _ in
            Task { await app.reloadSidebarCounts() }
        }
    }

    private var contextMenu: some View {
        Menu {
            contextOption(title: "Current Context", tag: "_current")
            if !app.contexts.isEmpty {
                Divider()
                ForEach(app.contexts) { context in
                    contextOption(title: context.name, tag: context.name)
                }
            }
        } label: {
            pillLabel(icon: "helm", title: app.contextDisplayName)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Kubernetes context")
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

    @ViewBuilder
    private func contextOption(title: String, tag: String) -> some View {
        Button {
            app.selectedContext = tag
        } label: {
            if app.selectedContext == tag {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func pillLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
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
    func scopePickerToolbar(app: AppModel) -> some View {
        modifier(ScopePickerToolbarModifier(app: app))
    }
}
