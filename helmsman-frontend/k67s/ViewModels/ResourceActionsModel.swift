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
    var rolloutHistoryTarget: RolloutHistoryTarget?
    var cancelTarget: TablePayload.Row?
    var drainTarget: TablePayload.Row?
    var replicasText = ""
    var isBusy = false
    var actionError: APIError?

    /// The resource being acted on (its API path segment + restart workload).
    var resource: ResourceType?

    var onMutated: () -> Void = {}

    func beginScale(_ row: TablePayload.Row, currentReplicas: String) {
        replicasText = currentReplicas
        scaleTarget = row
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
        await run {
            try await KubeAPIClient.shared.delete(
                ns: row.object.namespace ?? "", resource: resource.resource, name: row.object.name
            )
        }
        deleteTarget = nil
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

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        actionError = nil
        defer { isBusy = false }
        do {
            try await operation()
            onMutated()
        } catch let apiError as APIError {
            actionError = apiError
        } catch {
            actionError = .transport(error.localizedDescription)
        }
    }
}
