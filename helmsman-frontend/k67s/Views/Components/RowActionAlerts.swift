import SwiftUI

/// Attaches the Scale / Restart / Delete / Drain / CancelJob confirmation
/// modals plus the Rollout History sheet and a generic error alert,
/// all driven by `ResourceActionsModel`.
struct RowActionAlerts: ViewModifier {
    @Bindable var actions: ResourceActionsModel

    func body(content: Content) -> some View {
        content
            // Scale — title adapts to the actual resource kind.
            .alert("Scale \(actions.resource?.title ?? "Workload")", isPresented: presented(\.scaleTarget)) {
                TextField("Replicas", text: $actions.replicasText)
                    .labelsHidden()
                Button("Cancel", role: .cancel) { actions.scaleTarget = nil }
                Button("Scale") {
                    let row = actions.scaleTarget
                    let replicas = actions.replicasText
                    Task { await actions.performScale(row, replicas: replicas) }
                }
            } message: {
                Text("Enter the desired number of replicas for \"\(actions.scaleTarget?.object.name ?? "")\".")
            }

            // Restart
            .alert("Restart \(actions.restartTarget?.object.name ?? "")?", isPresented: presented(\.restartTarget)) {
                Button("Cancel", role: .cancel) { actions.restartTarget = nil }
                Button("Restart", role: .destructive) {
                    let row = actions.restartTarget
                    Task { await actions.performRestart(row) }
                }
            } message: {
                Text("This will trigger a rolling restart of all pods.")
            }

            // Delete
            .alert("Delete \(actions.deleteTarget?.object.name ?? "")?", isPresented: presented(\.deleteTarget)) {
                Button("Cancel", role: .cancel) { actions.deleteTarget = nil }
                Button("Delete", role: .destructive) {
                    let row = actions.deleteTarget
                    Task { await actions.performDelete(row) }
                }
            } message: {
                Text("This resource will be permanently deleted.")
            }

            // Force delete
            .alert("Force delete \(actions.forceDeleteTarget?.object.name ?? "")?", isPresented: presented(\.forceDeleteTarget)) {
                Button("Cancel", role: .cancel) { actions.forceDeleteTarget = nil }
                Button("Force Delete", role: .destructive) {
                    let row = actions.forceDeleteTarget
                    Task { await actions.performForceDelete(row) }
                }
            } message: {
                Text("Deletes immediately with grace period 0. Does not remove finalizers.")
            }

            // Trigger CronJob
            .alert("Trigger \(actions.triggerTarget?.object.name ?? "")?", isPresented: presented(\.triggerTarget)) {
                Button("Cancel", role: .cancel) { actions.triggerTarget = nil }
                Button("Trigger Now") {
                    let row = actions.triggerTarget
                    Task { await actions.performTriggerCronJob(row) }
                }
            } message: {
                Text("Creates a one-off Job from this CronJob's template.")
            }

            // Cancel Job
            .alert("Cancel \(actions.cancelTarget?.object.name ?? "")?", isPresented: presented(\.cancelTarget)) {
                Button("Cancel", role: .cancel) { actions.cancelTarget = nil }
                Button("Cancel Job", role: .destructive) {
                    let row = actions.cancelTarget
                    Task { await actions.performCancelJob(row) }
                }
            } message: {
                Text("The job will be suspended and its active pods deleted.")
            }

            // Drain Node
            .alert("Drain \(actions.drainTarget?.object.name ?? "")?", isPresented: presented(\.drainTarget)) {
                Button("Cancel", role: .cancel) { actions.drainTarget = nil }
                Button("Drain", role: .destructive) {
                    let row = actions.drainTarget
                    Task { await actions.performDrain(row) }
                }
            } message: {
                Text("The node will be cordoned and all evictable pods will be evicted.")
            }

            // Rollout History sheet
            .sheet(item: $actions.rolloutHistoryTarget) { target in
                RolloutHistorySheet(
                    ctx: target.ctx,
                    ns: target.ns,
                    workload: target.workload,
                    name: target.row.object.name,
                    onUndone: { actions.onMutated(nil) }
                )
            }

            // PVC Resize sheet
            .sheet(item: $actions.resizeTarget) { target in
                ResizePVCSheet(actions: actions, target: target)
            }

            // Delete with cascade options sheet
            .sheet(item: $actions.deleteOptionsTarget) { row in
                DeleteOptionsSheet(actions: actions, row: row)
            }

            // Generic error alert (last, catches all action errors)
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
            .bottomToast($actions.actionToast)
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
