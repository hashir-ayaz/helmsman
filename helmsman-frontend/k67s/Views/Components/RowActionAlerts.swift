import SwiftUI

/// Attaches the Scale / Restart / Delete confirmation modals (plus an error
/// alert) for a resource list, driven by `ResourceActionsModel`.
struct RowActionAlerts: ViewModifier {
    @Bindable var actions: ResourceActionsModel

    func body(content: Content) -> some View {
        content
            .alert("Scale Deployment", isPresented: presented(\.scaleTarget)) {
                TextField("Replicas", text: $actions.replicasText)
                    .labelsHidden()
                Button("Cancel", role: .cancel) { actions.scaleTarget = nil }
                Button("Scale") { Task { await actions.performScale() } }
            } message: {
                Text("Enter the desired number of replicas for \"\(actions.scaleTarget?.object.name ?? "")\".")
            }
            .alert("Restart \(actions.restartTarget?.object.name ?? "")?", isPresented: presented(\.restartTarget)) {
                Button("Cancel", role: .cancel) { actions.restartTarget = nil }
                Button("Restart", role: .destructive) { Task { await actions.performRestart() } }
            } message: {
                Text("This will trigger a rolling restart of all pods.")
            }
            .alert("Delete \(actions.deleteTarget?.object.name ?? "")?", isPresented: presented(\.deleteTarget)) {
                Button("Cancel", role: .cancel) { actions.deleteTarget = nil }
                Button("Delete", role: .destructive) { Task { await actions.performDelete() } }
            } message: {
                Text("This resource will be permanently deleted.")
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { actions.actionError != nil },
                    set: { if !$0 { actions.actionError = nil } }
                )
            ) {
                Button("OK") { actions.actionError = nil }
            } message: {
                Text(actions.actionError?.errorDescription ?? "Unknown error")
            }
    }

    /// A Bool presentation binding derived from an optional row target.
    private func presented(_ keyPath: ReferenceWritableKeyPath<ResourceActionsModel, TablePayload.Row?>) -> Binding<Bool> {
        Binding(
            get: { actions[keyPath: keyPath] != nil },
            set: { if !$0 { actions[keyPath: keyPath] = nil } }
        )
    }
}

extension View {
    func rowActionAlerts(_ actions: ResourceActionsModel) -> some View {
        modifier(RowActionAlerts(actions: actions))
    }
}
