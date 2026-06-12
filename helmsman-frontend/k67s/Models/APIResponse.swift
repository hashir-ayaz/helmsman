import Foundation

/// Standard envelope wrapping every JSON endpoint: `{ "data": …, "error": … }`.
struct APIResponse<T: Decodable>: Decodable {
    let data: T?
    let error: String?
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
        case .transport(let message): "Could not reach the backend: \(message)"
        case .decoding(let message): "Failed to decode response: \(message)"
        }
    }

    /// True for 403 — read-only or namespace-scoped kubeconfigs hit this normally.
    var isRBAC: Bool {
        if case .forbidden = self { return true }
        return false
    }

    static func from(status: Int, message: String) -> APIError {
        switch status {
        case 401: .unauthorized(message)
        case 403: .forbidden(message)
        case 404: .notFound(message)
        case 409: .conflict(message)
        case 422: .invalid(message)
        default: .server(message)
        }
    }
}
