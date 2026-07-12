import AppKit
import SwiftUI

/// Lists and manages active port-forward sessions for the current context.
@Observable
@MainActor
final class PortForwardsModel {
    var sessions: [PortForwardSession] = []
    var isLoading = false
    var error: APIError?

    private var pollTask: Task<Void, Never>?

    var activeCount: Int {
        sessions.filter(\.isActive).count
    }

    func startPolling(ctx: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh(ctx: ctx)
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(ctx: String) async {
        isLoading = sessions.isEmpty
        error = nil
        do {
            sessions = try await KubeAPIClient.shared.listPortForwards(ctx: ctx)
        } catch let apiError as APIError {
            error = apiError
        } catch let transportError {
            error = .transport(transportError.localizedDescription)
        }
        isLoading = false
    }

    func stop(ctx: String, session: PortForwardSession) async {
        do {
            _ = try await KubeAPIClient.shared.stopPortForward(ctx: ctx, id: session.id)
            await refresh(ctx: ctx)
        } catch let apiError as APIError {
            error = apiError
        } catch let transportError {
            error = .transport(transportError.localizedDescription)
        }
    }

    func remove(ctx: String, session: PortForwardSession) async {
        do {
            try await KubeAPIClient.shared.removePortForward(ctx: ctx, id: session.id)
            await refresh(ctx: ctx)
        } catch let apiError as APIError {
            error = apiError
        } catch let transportError {
            error = .transport(transportError.localizedDescription)
        }
    }

    func openInBrowser(_ session: PortForwardSession) {
        guard let url = session.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ session: PortForwardSession) {
        guard let url = session.browserURL?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}
