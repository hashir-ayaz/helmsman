import Foundation

/// Live reachability of one kubeconfig context, as shown on a picker card.
enum ContextHealth: Equatable {
    case probing
    case reachable
    /// Title, message and tip come from the carried `APIError`.
    case unreachable(APIError)
}
