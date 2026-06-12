import SwiftUI

/// Loads a resource's YAML for editing and applies edits via server-side apply.
@Observable
@MainActor
final class YAMLEditorModel {
    var text = ""
    private(set) var originalText = ""
    private(set) var kind = ""
    private(set) var isLoading = false
    private(set) var isApplying = false
    var error: APIError?
    var applied = false

    private let target: YAMLWindowTarget

    init(target: YAMLWindowTarget) {
        self.target = target
    }

    var isDirty: Bool { text != originalText }

    /// Header label, e.g. "Pod/my-pod".
    var headerLabel: String {
        kind.isEmpty ? target.name : "\(kind)/\(target.name)"
    }

    var namespace: String { target.namespace }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let yaml = try await KubeAPIClient.shared.getYAML(
                ctx: target.ctx, ns: target.namespace,
                resource: target.resource, name: target.name
            )
            text = yaml
            originalText = yaml
            kind = Self.parseKind(from: yaml)
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func apply() async {
        isApplying = true
        error = nil
        applied = false
        defer { isApplying = false }
        do {
            try await KubeAPIClient.shared.apply(ctx: target.ctx, yaml: text)
            applied = true
            await load() // Reflect the server's normalized object.
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// Extracts the top-level `kind:` value for the header.
    private static func parseKind(from yaml: String) -> String {
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("kind:") {
                return line.dropFirst("kind:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
