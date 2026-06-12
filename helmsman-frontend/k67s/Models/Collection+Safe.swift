import Foundation

extension Collection {
    /// Returns the element at `index` if in bounds, otherwise `nil`.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
