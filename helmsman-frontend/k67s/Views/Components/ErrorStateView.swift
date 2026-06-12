import SwiftUI

/// Full-area error state. 403/RBAC is presented as an informational "access
/// denied" without a retry — scoped kubeconfigs hit it normally.
struct ErrorStateView: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                error.isRBAC ? "Access Denied" : "Couldn’t Load",
                systemImage: error.isRBAC ? "lock.shield" : "exclamationmark.triangle"
            )
        } description: {
            Text(error.errorDescription ?? "Unknown error")
        } actions: {
            if !error.isRBAC {
                Button("Retry", action: retry)
            }
        }
    }
}
