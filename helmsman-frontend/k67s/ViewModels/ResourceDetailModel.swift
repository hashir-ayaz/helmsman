import SwiftUI

/// Loads the full raw object and (lazily) the YAML for one selected resource.
@Observable
final class ResourceDetailModel {
    private(set) var object: JSONValue?
    private(set) var yaml: String?
    private(set) var isLoadingObject = false
    private(set) var isLoadingYAML = false
    var error: APIError?

    func loadObject(ctx: String, ns: String?, resource: ResourceType, name: String) async {
        guard object == nil else { return }
        isLoadingObject = true
        defer { isLoadingObject = false }
        do {
            object = try await KubeAPIClient.shared.getObject(
                ctx: ctx, ns: ns, resource: resource.resource, name: name
            )
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func loadYAML(ctx: String, ns: String?, resource: ResourceType, name: String) async {
        guard yaml == nil else { return }
        isLoadingYAML = true
        defer { isLoadingYAML = false }
        do {
            yaml = try await KubeAPIClient.shared.getYAML(
                ctx: ctx, ns: ns, resource: resource.resource, name: name
            )
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }
}
