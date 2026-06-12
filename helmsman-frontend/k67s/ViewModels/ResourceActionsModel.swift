import SwiftUI

/// Coordinates the scale / restart / delete modals for a resource list and runs
/// the mutations. Set `onMutated` to refresh the list after a successful change.
@Observable
@MainActor
final class ResourceActionsModel {
    var scaleTarget: TablePayload.Row?
    var restartTarget: TablePayload.Row?
    var deleteTarget: TablePayload.Row?
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

    func performScale() async {
        guard let row = scaleTarget, let replicas = Int(replicasText.trimmingCharacters(in: .whitespaces)) else { return }
        await run {
            try await KubeAPIClient.shared.scale(
                ns: row.object.namespace ?? "", name: row.object.name, replicas: replicas
            )
        }
        scaleTarget = nil
    }

    func performRestart() async {
        guard let row = restartTarget, let workload = resource?.restartWorkload else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        await run {
            try await KubeAPIClient.shared.restart(
                ns: row.object.namespace ?? "", workload: workload, name: row.object.name, restartedAt: stamp
            )
        }
        restartTarget = nil
    }

    func performDelete() async {
        guard let row = deleteTarget, let resource else { return }
        await run {
            try await KubeAPIClient.shared.delete(
                ns: row.object.namespace ?? "", resource: resource.resource, name: row.object.name
            )
        }
        deleteTarget = nil
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
