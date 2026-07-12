import SwiftUI

/// Carries all context needed to open the Rollout History sheet.
struct RolloutHistoryTarget: Identifiable {
    let row: TablePayload.Row
    let ctx: String
    let ns: String
    let workload: String
    var id: String { row.id }
}

/// Coordinates the scale / restart / delete modals for a resource list and runs
/// the mutations. Set `onMutated` to refresh the list after a successful change.
@Observable
@MainActor
final class ResourceActionsModel {
    var scaleTarget: TablePayload.Row?
    var restartTarget: TablePayload.Row?
    var deleteTarget: TablePayload.Row?
    var forceDeleteTarget: TablePayload.Row?
    var deleteOptionsTarget: TablePayload.Row?
    var deletePropagationPolicy: DeletePropagationPolicy = .background
    var deleteImmediate = false
    var triggerTarget: TablePayload.Row?
    var rolloutHistoryTarget: RolloutHistoryTarget?
    var cancelTarget: TablePayload.Row?
    var drainTarget: TablePayload.Row?
    var resizeTarget: ResizePVCTarget?
    var replicasText = ""
    var resizeValueText = ""
    var resizeUnit: PVCResizeUnit = .gi
    var isBusy = false
    var actionError: APIError?
    var actionToast: String?

    /// The resource being acted on (its API path segment + restart workload).
    var resource: ResourceType?

    var onMutated: (TablePayload.Row.ID?) -> Void = { _ in }

    private var toastDismissTask: Task<Void, Never>?

    func showActionToast(_ message: String) {
        toastDismissTask?.cancel()
        actionToast = message
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            actionToast = nil
        }
    }

    func beginScale(_ row: TablePayload.Row, currentReplicas: String) {
        replicasText = currentReplicas
        scaleTarget = row
    }

    func beginResize(_ target: ResizePVCTarget) {
        resizeValueText = target.initialValue
        resizeUnit = PVCResizeUnit(rawValue: target.initialUnit) ?? .gi
        resizeTarget = target
    }

    func performResize(_ target: ResizePVCTarget?) async {
        guard let target else { return }
        let value = resizeValueText.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, Double(value) != nil else { return }
        let storage = "\(value)\(resizeUnit.rawValue)"
        await run {
            try await KubeAPIClient.shared.resizePVC(
                ns: target.row.object.namespace ?? "",
                name: target.row.object.name,
                storage: storage
            )
        }
        if actionError == nil {
            showActionToast("Resize requested for \(target.namespaceName) to \(storage)")
        }
        resizeTarget = nil
    }

    // The target row is passed in (captured synchronously by the alert button)
    // rather than read from `self`: dismissing an `.alert` nils the *Target
    // properties before this async work runs, so reading them here would always
    // see `nil` and silently no-op.
    func performScale(_ row: TablePayload.Row?, replicas replicasText: String) async {
        guard let row,
              let workload = resource?.scaleWorkload,
              let replicas = Int(replicasText.trimmingCharacters(in: .whitespaces)) else { return }
        await run {
            try await KubeAPIClient.shared.scale(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name, replicas: replicas
            )
        }
        scaleTarget = nil
    }

    func performRestart(_ row: TablePayload.Row?) async {
        guard let row, let workload = resource?.restartWorkload else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        await run {
            try await KubeAPIClient.shared.restart(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name, restartedAt: stamp
            )
        }
        restartTarget = nil
    }

    func performDelete(_ row: TablePayload.Row?) async {
        guard let row, let resource else { return }
        let rowID = row.id
        await run(mutatedRowID: rowID) {
            try await KubeAPIClient.shared.delete(
                ns: row.object.namespace ?? "", resource: resource.resource, name: row.object.name
            )
        }
        deleteTarget = nil
    }

    func performForceDelete(_ row: TablePayload.Row?) async {
        guard let row, let resource else { return }
        let rowID = row.id
        await run(mutatedRowID: rowID) {
            try await KubeAPIClient.shared.delete(
                ns: row.object.namespace ?? "",
                resource: resource.resource,
                name: row.object.name,
                gracePeriodSeconds: 0
            )
        }
        forceDeleteTarget = nil
        if actionError == nil {
            showActionToast("Force deleted \(row.object.name)")
        }
    }

    func beginDeleteWithOptions(_ row: TablePayload.Row) {
        deletePropagationPolicy = .background
        deleteImmediate = false
        deleteOptionsTarget = row
    }

    func performDeleteWithOptions(_ row: TablePayload.Row?) async {
        guard let row, let resource else { return }
        let rowID = row.id
        let policy = deletePropagationPolicy.rawValue
        let grace = deleteImmediate ? 0 : nil
        await run(mutatedRowID: rowID) {
            try await KubeAPIClient.shared.delete(
                ns: row.object.namespace ?? "",
                resource: resource.resource,
                name: row.object.name,
                gracePeriodSeconds: grace,
                propagationPolicy: policy
            )
        }
        deleteOptionsTarget = nil
        if actionError == nil {
            let policyLabel = deletePropagationPolicy.rawValue.lowercased()
            showActionToast("Deleted \(row.object.name) (\(policyLabel) cascade)")
        }
    }

    func performTriggerCronJob(_ row: TablePayload.Row?) async {
        guard let row else { return }
        let ns = row.object.namespace ?? ""
        let cronJobName = row.object.name
        isBusy = true
        actionError = nil
        defer { isBusy = false }
        do {
            let created = try await KubeAPIClient.shared.triggerCronJob(ns: ns, name: cronJobName)
            onMutated(nil)
            showActionToast("Created Job \(created.name)")
        } catch let apiError as APIError {
            actionError = apiError
        } catch {
            actionError = .transport(error.localizedDescription)
        }
        triggerTarget = nil
    }

    func performRolloutPause(_ row: TablePayload.Row?) async {
        guard let row, let workload = resource?.restartWorkload else { return }
        await run {
            try await KubeAPIClient.shared.rolloutPause(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name
            )
        }
    }

    func performRolloutResume(_ row: TablePayload.Row?) async {
        guard let row, let workload = resource?.restartWorkload else { return }
        await run {
            try await KubeAPIClient.shared.rolloutResume(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name
            )
        }
    }

    func performSuspend(_ row: TablePayload.Row?) async {
        guard let row, let workload = resource?.suspendWorkload else { return }
        await run {
            try await KubeAPIClient.shared.suspend(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name
            )
        }
    }

    func performResume(_ row: TablePayload.Row?) async {
        guard let row, let workload = resource?.suspendWorkload else { return }
        await run {
            try await KubeAPIClient.shared.resume(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name
            )
        }
    }

    func performCancelJob(_ row: TablePayload.Row?) async {
        guard let row else { return }
        await run {
            try await KubeAPIClient.shared.cancelJob(
                ns: row.object.namespace ?? "", name: row.object.name
            )
        }
        cancelTarget = nil
    }

    func performDrain(_ row: TablePayload.Row?) async {
        guard let row else { return }
        await run {
            try await KubeAPIClient.shared.drainNode(name: row.object.name)
        }
        drainTarget = nil
    }

    private func run(mutatedRowID: TablePayload.Row.ID? = nil, _ operation: () async throws -> Void) async {
        isBusy = true
        actionError = nil
        defer { isBusy = false }
        do {
            try await operation()
            onMutated(mutatedRowID)
        } catch let apiError as APIError {
            actionError = apiError
        } catch {
            actionError = .transport(error.localizedDescription)
        }
    }
}
