import Network

/// Lightweight reachability check used at launch before hitting the backend.
enum NetworkConnectivity {
    /// `true` when Wi‑Fi, Ethernet, or cellular is available (loopback alone does not count).
    static func hasUsableNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: Self.isUsable(path))
            }
            monitor.start(queue: DispatchQueue(label: "helmsman.network.connectivity"))
        }
    }

    private static func isUsable(_ path: NWPath) -> Bool {
        guard path.status == .satisfied else { return false }
        return path.availableInterfaces.contains { iface in
            switch iface.type {
            case .wifi, .wiredEthernet, .cellular:
                return true
            default:
                return false
            }
        }
    }
}
