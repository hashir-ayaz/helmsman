import SwiftUI

/// Sidebar navigation — Overview is a custom dashboard; resources use the generic list.
enum SidebarDestination: Hashable {
    case overview
    case resource(ResourceType)
}

/// App-wide state: selected context/namespace/resource, plus the lists used to
/// populate the sidebar pickers.
@Observable
final class AppModel {
    static let allNamespaces = "All Namespaces"

    enum ConnectionPhase: Equatable {
        case connecting
        case ready
        case failed(title: String, message: String, code: String?)
    }

    var connectionPhase: ConnectionPhase = .connecting
    var contexts: [ContextInfo] = []
    var selectedContext = "_current"
    var namespaces: [String] = []
    var selectedNamespace = AppModel.allNamespaces
    var selectedDestination: SidebarDestination = .overview

    var selectedResource: ResourceType? {
        if case .resource(let resource) = selectedDestination { return resource }
        return nil
    }

    func selectResource(_ resource: ResourceType) {
        selectedDestination = .resource(resource)
    }

    /// `nil` means "all namespaces" (the cluster-scoped list path).
    var namespaceParam: String? {
        selectedNamespace == Self.allNamespaces ? nil : selectedNamespace
    }

    var namespacePickerOptions: [String] {
        [Self.allNamespaces] + namespaces
    }

    var isReady: Bool {
        if case .ready = connectionPhase { return true }
        return false
    }

    private static let healthPollInterval: Duration = .milliseconds(150)
    private static let healthTimeout: Duration = .seconds(20)

    func bootstrap() async {
        connectionPhase = .connecting

        guard await waitForBackend() else { return }

        do {
            let status = try await KubeAPIClient.shared.fetchStatus()
            if !status.ready {
                connectionPhase = .failed(
                    title: Self.title(for: status.code),
                    message: status.message.isEmpty
                        ? "There was an error connecting to your cluster."
                        : status.message,
                    code: status.code
                )
                return
            }
        } catch {
            connectionPhase = .failed(
                title: "Connection Failed",
                message: "There was an error connecting to your cluster.",
                code: nil
            )
            return
        }

        guard await loadContexts() else { return }
        await loadNamespaces()
        connectionPhase = .ready
    }

    func retryConnection() async {
        await bootstrap()
    }

    @discardableResult
    func loadContexts() async -> Bool {
        do {
            contexts = try await KubeAPIClient.shared.listContexts()
            return true
        } catch let error as APIError {
            setFailed(from: error)
            return false
        } catch {
            connectionPhase = .failed(
                title: "Connection Failed",
                message: "There was an error connecting to your cluster.",
                code: nil
            )
            return false
        }
    }

    /// Namespaces are loaded through the generic endpoint — no typed model. A
    /// scoped kubeconfig may forbid listing them, which just leaves the picker
    /// at "All Namespaces".
    func loadNamespaces() async {
        for attempt in 0..<2 {
            do {
                let table = try await KubeAPIClient.shared.listResources(
                    ctx: selectedContext,
                    ns: nil,
                    resource: "namespaces"
                )
                namespaces = table.rows.map(\.object.name).sorted()
                if !namespaces.contains(selectedNamespace),
                   selectedNamespace != Self.allNamespaces {
                    selectedNamespace = Self.allNamespaces
                }
                return
            } catch let error as APIError where error.isRBAC {
                namespaces = []
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(200))
                    continue
                }
                namespaces = []
                return
            }
        }
    }

    func contextDidChange() async {
        selectedNamespace = Self.allNamespaces
        await loadNamespaces()
    }

    @discardableResult
    private func waitForBackend() async -> Bool {
        let deadline = ContinuousClock.now + Self.healthTimeout
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return false }
            do {
                try await KubeAPIClient.shared.checkHealth()
                return true
            } catch {
                try? await Task.sleep(for: Self.healthPollInterval)
            }
        }
        connectionPhase = .failed(
            title: "Connection Failed",
            message: "Could not reach the Helmsman backend. If you're developing locally, run `make run` in helmsman-api and try again.",
            code: "backend_unreachable"
        )
        return false
    }

    private func setFailed(from error: APIError) {
        connectionPhase = .failed(
            title: "Connection Failed",
            message: error.errorDescription ?? "There was an error connecting to your cluster.",
            code: nil
        )
    }

    private static func title(for code: String) -> String {
        switch code {
        case "kubeconfig_not_found": "Kubeconfig Not Found"
        case "kubeconfig_invalid": "Invalid Kubeconfig"
        case "no_contexts": "No Contexts Configured"
        case "backend_unreachable": "Connection Failed"
        default: "Connection Failed"
        }
    }
}
