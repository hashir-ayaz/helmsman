import Foundation

/// Standard envelope wrapping every JSON endpoint: `{ "data": …, "error": …, "code": … }`.
struct APIResponse<T: Decodable>: Decodable {
    let data: T?
    let error: String?
    let code: String?
}

/// Response from POST .../cronjobs/{name}/trigger.
struct CreatedJobResponse: Decodable, Sendable {
    let name: String
    let namespace: String
}

/// API failures mapped from HTTP status so the UI can react per category.
enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized(String)   // 401
    case forbidden(String)      // 403 — RBAC / permission denied
    case notFound(String)       // 404
    case conflict(String)       // 409
    case invalid(String)        // 422 — validation error
    case server(String)         // 500
    case unavailable(code: String, message: String) // 502 / 503 / 504
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL."
        case .invalidResponse: "Invalid server response."
        case .unauthorized(let message): message.isEmpty ? "Unauthorized." : message
        case .forbidden(let message): message.isEmpty ? "Access denied." : message
        case .notFound(let message): message.isEmpty ? "Not found." : message
        case .conflict(let message): message.isEmpty ? "Conflict." : message
        case .invalid(let message): message.isEmpty ? "Invalid request." : message
        case .server(let message): message.isEmpty ? "Internal server error." : message
        case .unavailable(_, let message):
            message.isEmpty ? "The cluster is currently unavailable." : message
        case .transport(let message): "Could not reach the backend: \(message)"
        case .decoding(let message): "Failed to decode response: \(message)"
        }
    }

    /// Typed backend code when present (`kubeconfig_not_found`, `cluster_unreachable`, …).
    var code: String? {
        switch self {
        case .unavailable(let code, _): code.isEmpty ? nil : code
        default: nil
        }
    }

    /// True for 403 — read-only or namespace-scoped kubeconfigs hit this normally.
    var isRBAC: Bool {
        if case .forbidden = self { return true }
        return false
    }

    /// True when the API server is unreachable or timed out (or kubeconfig is unusable mid-request).
    var isClusterConnectivity: Bool {
        switch self {
        case .unavailable(let code, _):
            switch code {
            case "cluster_unreachable", "cluster_timeout",
                 "kubeconfig_not_found", "kubeconfig_invalid", "no_contexts":
                return true
            default:
                return code.hasPrefix("cluster_") || code.hasPrefix("kubeconfig_")
            }
        default:
            return false
        }
    }

    /// Short title for full-pane error UIs.
    var displayTitle: String {
        if isRBAC { return "Access Denied" }
        switch code {
        case "cluster_unreachable": return "Can’t Reach Cluster"
        case "cluster_timeout": return "Cluster Timed Out"
        case "kubeconfig_not_found": return "Kubeconfig Not Found"
        case "kubeconfig_invalid": return "Invalid Kubeconfig"
        case "no_contexts": return "No Contexts Configured"
        case "cluster_auth": return "Authentication Failed"
        default: return "Couldn’t Load"
        }
    }

    /// Optional tip shown under connectivity failures.
    var displayTip: String? {
        switch code {
        case "cluster_unreachable":
            return "Your kubeconfig looks fine, but the API server isn’t responding. Start the cluster (Docker Desktop, kind, minikube, etc.) and try again."
        case "cluster_timeout":
            return "Check your network or VPN, or whether the API server is overloaded, then try again."
        case "kubeconfig_not_found":
            return "Point KUBECONFIG at your config file, or place one at ~/.kube/config."
        case "kubeconfig_invalid":
            return "Check that your kubeconfig is valid YAML and contains at least one context."
        case "no_contexts":
            return "Add a cluster context to your kubeconfig, then try again."
        case "cluster_auth":
            return "Your login for this cluster may have expired, or its auth plugin is missing. Refresh your credentials with kubectl — for example kubectl get nodes — then try again."
        default:
            return nil
        }
    }

    static func from(status: Int, message: String, code: String? = nil) -> APIError {
        switch status {
        case 401: .unauthorized(message)
        case 403: .forbidden(message)
        case 404: .notFound(message)
        case 409: .conflict(message)
        case 422: .invalid(message)
        case 502, 503, 504:
            .unavailable(code: code ?? "", message: message)
        default:
            if let code, !code.isEmpty,
               code.hasPrefix("cluster_") || code.hasPrefix("kubeconfig_") || code == "no_contexts" {
                .unavailable(code: code, message: message)
            } else {
                .server(message)
            }
        }
    }
}
