import SwiftUI

/// Manages data for the Rollout History sheet — loads history entries and
/// performs undo by patching the workload back to a previous revision.
@Observable
@MainActor
final class RolloutHistorySheetModel {
    private(set) var revisions: [RevisionEntry] = []
    private(set) var isLoading = false
    private(set) var isUndoing = false
    var error: APIError?

    func load(ctx: String, ns: String, workload: String, name: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            revisions = try await KubeAPIClient.shared.getRolloutHistory(
                ctx: ctx, ns: ns, workload: workload, name: name
            )
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// Returns `true` on success so the sheet can auto-dismiss.
    func undo(ctx: String, ns: String, workload: String, name: String, toRevision: Int64) async -> Bool {
        isUndoing = true
        error = nil
        defer { isUndoing = false }
        do {
            try await KubeAPIClient.shared.rolloutUndo(
                ctx: ctx, ns: ns, workload: workload, name: name, toRevision: toRevision
            )
            return true
        } catch let apiError as APIError {
            error = apiError
            return false
        } catch {
            self.error = .transport(error.localizedDescription)
            return false
        }
    }
}
