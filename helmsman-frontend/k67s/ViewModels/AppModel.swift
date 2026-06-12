import SwiftUI

/// App-wide state: selected context/namespace/resource, plus the lists used to
/// populate the sidebar pickers.
@Observable
final class AppModel {
    static let allNamespaces = "All Namespaces"

    var contexts: [ContextInfo] = []
    var selectedContext = "_current"
    var namespaces: [String] = []
    var selectedNamespace = AppModel.allNamespaces
    var selectedResource: ResourceType? = ResourceType.all.first
    var globalError: APIError?

    /// `nil` means "all namespaces" (the cluster-scoped list path).
    var namespaceParam: String? {
        selectedNamespace == Self.allNamespaces ? nil : selectedNamespace
    }

    var namespacePickerOptions: [String] {
        [Self.allNamespaces] + namespaces
    }

    func bootstrap() async {
        await loadContexts()
        await loadNamespaces()
    }

    func loadContexts() async {
        do {
            contexts = try await KubeAPIClient.shared.listContexts()
        } catch let error as APIError {
            globalError = error
        } catch {
            globalError = .transport(error.localizedDescription)
        }
    }

    /// Namespaces are loaded through the generic endpoint — no typed model. A
    /// scoped kubeconfig may forbid listing them, which just leaves the picker
    /// at "All Namespaces".
    func loadNamespaces() async {
        do {
            let table = try await KubeAPIClient.shared.listResources(
                ctx: selectedContext,
                ns: nil,
                resource: "namespaces"
            )
            namespaces = table.rows.map(\.object.name).sorted()
        } catch {
            namespaces = []
        }
    }
}
