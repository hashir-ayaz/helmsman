import SwiftUI

/// Full-area error state. 403/RBAC is presented as an informational "access
/// denied" without a retry — scoped kubeconfigs hit it normally. Connectivity
/// failures get a typed title + tip instead of raw dial errors.
struct ErrorStateView: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(error.displayTitle)
            } icon: {
                Image(systemName: symbolName)
                    .foregroundStyle(symbolColor)
                    .symbolRenderingMode(.hierarchical)
            }
        } description: {
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Unknown error")
                    .multilineTextAlignment(.center)
                if let tip = error.displayTip {
                    TipCallout(text: tip)
                }
            }
        } actions: {
            if !error.isRBAC {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(HelmsmanBrand.amber)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbolName: String {
        if error.isRBAC { return "lock.shield" }
        if error.isClusterConnectivity { return "antenna.radiowaves.left.and.right.slash" }
        return "exclamationmark.triangle"
    }

    private var symbolColor: Color {
        if error.isRBAC { return .secondary }
        if error.isClusterConnectivity { return HelmsmanBrand.warning }
        return HelmsmanBrand.warning
    }
}
