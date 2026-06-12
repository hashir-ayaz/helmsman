import Foundation

struct WatchEvent: Decodable, Sendable {
    let type: String
    let name: String
    let namespace: String?
}
