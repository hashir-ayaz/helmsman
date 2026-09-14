import SwiftUI

/// Context pill opens the full-window cluster picker. Namespace pill is a menu.
struct ScopePickerPills: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: 8) {
            contextButton
            namespaceMenu
        }
        .onChange(of: app.selectedNamespace) { _, _ in
            Task { await app.reloadSidebarCounts() }
        }
    }

    private var contextButton: some View {
        Button {
            app.showContextPicker()
        } label: {
            pillLabel(icon: "helm", title: app.contextDisplayName, trailing: "arrow.left.arrow.right")
        }
        .buttonStyle(.plain)
        .help("Switch cluster")
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

    private func pillLabel(icon: String, title: String, trailing: String = "chevron.down") -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: trailing)
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
