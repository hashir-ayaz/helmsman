import SwiftUI

/// Full-area error state. 403/RBAC is presented as an informational "access
/// denied" without a retry — scoped kubeconfigs hit it normally. Connectivity
/// failures get a typed title + tip instead of raw dial errors.
struct ErrorStateView: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.displayTitle, systemImage: symbolName)
        } description: {
            VStack(spacing: 8) {
                Text(error.errorDescription ?? "Unknown error")
                if let tip = error.displayTip {
                    Text(tip)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        } actions: {
            if !error.isRBAC {
                Button("Retry", action: retry)
            }
        }
    }

    private var symbolName: String {
        if error.isRBAC { return "lock.shield" }
        if error.isClusterConnectivity { return "antenna.radiowaves.left.and.right.slash" }
        return "exclamationmark.triangle"
    }
}
