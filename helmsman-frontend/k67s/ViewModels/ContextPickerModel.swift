import Foundation

/// Drives the context picker grid: per-card health probes and the single
/// in-flight connect. Owned as @State by ContextPickerView.
@Observable
@MainActor
final class ContextPickerModel {
    private(set) var health: [String: ContextHealth] = [:]
    /// Name of the context being connected, or nil. Only one connect runs at a time.
    private(set) var connectingContext: String?

    /// Probes every context in parallel and fills `health` as results arrive.
    /// Cancellation-aware: the view re-runs this through `.task(id:)`, which
    /// cancels the previous run and its child tasks.
    func probeAll(_ contexts: [ContextInfo]) async {
        for context in contexts { health[context.name] = .probing }
        await withTaskGroup(of: (String, ContextHealth).self) { group in
            for context in contexts {
                group.addTask { (context.name, await Self.probe(context.name)) }
            }
            for await (name, result) in group {
                guard !Task.isCancelled else { return }
                health[name] = result
            }
        }
    }

    /// Connects through AppModel so the app-wide state changes in one place.
    /// A failure overwrites the card's health so the error shows inline.
    func connect(_ context: ContextInfo, app: AppModel) async {
        guard connectingContext == nil else { return }
        connectingContext = context.name
        defer { connectingContext = nil }
        if let error = await app.connect(to: context.name) {
            health[context.name] = .unreachable(error)
        }
    }

    private static func probe(_ name: String) async -> ContextHealth {
        do {
            let status = try await KubeAPIClient.shared.fetchContextStatus(ctx: name)
            if let failure = status.failure { return .unreachable(failure) }
            return .reachable
        } catch let error as APIError {
            return .unreachable(error)
        } catch {
            return .unreachable(.transport(error.localizedDescription))
        }
    }
}
