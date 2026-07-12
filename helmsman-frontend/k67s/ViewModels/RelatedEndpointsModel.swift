import Foundation

/// One address entry from Endpoints or EndpointSlice objects.
struct EndpointAddressEntry: Identifiable, Hashable, Sendable {
    let id: String
    let display: String
    let podName: String?
    let ready: Bool
}

/// Parses Endpoints / EndpointSlice JSON into displayable address entries.
enum EndpointAddressParser {
    static func fromEndpoints(_ object: JSONValue) -> [EndpointAddressEntry] {
        var result: [EndpointAddressEntry] = []
        for (subsetIndex, subset) in (object["subsets"]?.arrayValue ?? []).enumerated() {
            let ports = (subset["ports"]?.arrayValue ?? []).compactMap { portNumber(from: $0) }
            for (addrIndex, addr) in (subset["addresses"]?.arrayValue ?? []).enumerated() {
                appendAddress(
                    &result,
                    ip: addr["ip"]?.stringValue,
                    podName: podName(from: addr["targetRef"]),
                    ports: ports,
                    ready: true,
                    idPrefix: "ready-\(subsetIndex)-\(addrIndex)"
                )
            }
            for (addrIndex, addr) in (subset["notReadyAddresses"]?.arrayValue ?? []).enumerated() {
                appendAddress(
                    &result,
                    ip: addr["ip"]?.stringValue,
                    podName: podName(from: addr["targetRef"]),
                    ports: ports,
                    ready: false,
                    idPrefix: "notready-\(subsetIndex)-\(addrIndex)"
                )
            }
        }
        return result
    }

    static func fromEndpointSlices(_ objects: [JSONValue]) -> [EndpointAddressEntry] {
        var result: [EndpointAddressEntry] = []
        for (sliceIndex, slice) in objects.enumerated() {
            let ports = (slice["ports"]?.arrayValue ?? []).compactMap { portNumber(from: $0) }
            for (epIndex, ep) in (slice["endpoints"]?.arrayValue ?? []).enumerated() {
                let ready = ep["conditions"]?["ready"]?.boolValue ?? true
                let pod = podName(from: ep["targetRef"])
                for (addrIndex, addr) in (ep["addresses"]?.arrayValue ?? []).enumerated() {
                    let ip = addr.stringValue
                    appendAddress(
                        &result,
                        ip: ip,
                        podName: pod,
                        ports: ports,
                        ready: ready,
                        idPrefix: "slice-\(sliceIndex)-\(epIndex)-\(addrIndex)"
                    )
                }
            }
        }
        return result
    }

    private static func appendAddress(
        _ result: inout [EndpointAddressEntry],
        ip: String?,
        podName: String?,
        ports: [String],
        ready: Bool,
        idPrefix: String
    ) {
        guard let ip, !ip.isEmpty else { return }
        if ports.isEmpty {
            result.append(EndpointAddressEntry(
                id: "\(idPrefix)-\(ip)",
                display: ip,
                podName: podName,
                ready: ready
            ))
        } else {
            for port in ports {
                result.append(EndpointAddressEntry(
                    id: "\(idPrefix)-\(ip)-\(port)",
                    display: "\(ip):\(port)",
                    podName: podName,
                    ready: ready
                ))
            }
        }
    }

    private static func podName(from targetRef: JSONValue?) -> String? {
        guard targetRef?["kind"]?.stringValue == "Pod",
              let name = targetRef?["name"]?.stringValue,
              !name.isEmpty else { return nil }
        return name
    }

    private static func portNumber(from port: JSONValue) -> String? {
        guard let value = port["port"] else { return nil }
        switch value {
        case .int(let n): return String(n)
        case .double(let n): return String(Int(n))
        case .string(let s): return s
        default: return value.displayString.isEmpty ? nil : value.displayString
        }
    }
}

/// Loads Endpoints (and EndpointSlice fallback) for a Service by name.
@Observable
@MainActor
final class RelatedEndpointsModel {
    private(set) var addresses: [EndpointAddressEntry] = []
    private(set) var source: String = ""
    private(set) var isLoading = false
    private(set) var error: APIError?

    var readyCount: Int { addresses.filter(\.ready).count }
    var notReadyCount: Int { addresses.filter { !$0.ready }.count }

    func load(ctx: String, namespace: String, serviceName: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: ctx,
                ns: namespace,
                resource: "endpoints",
                name: serviceName
            )
            let parsed = EndpointAddressParser.fromEndpoints(object)
            if !parsed.isEmpty {
                addresses = parsed
                source = "Endpoints"
                return
            }
        } catch let apiError as APIError {
            if case .notFound = apiError {
                // Fall through to EndpointSlices.
            } else {
                addresses = []
                error = apiError
                return
            }
        } catch {
            addresses = []
            self.error = .transport(error.localizedDescription)
            return
        }

        do {
            let table = try await KubeAPIClient.shared.listResources(
                ctx: ctx,
                ns: namespace,
                resource: "endpointslices.discovery.k8s.io",
                labelSelector: "kubernetes.io/service-name=\(serviceName)"
            )
            let objects = await fetchSliceObjects(ctx: ctx, namespace: namespace, rows: table.rows)
            let parsed = EndpointAddressParser.fromEndpointSlices(objects)
            addresses = parsed
            source = parsed.isEmpty ? "" : "EndpointSlices"
            if parsed.isEmpty {
                source = ""
            }
        } catch let apiError as APIError {
            addresses = []
            error = apiError
        } catch let transportError {
            addresses = []
            error = .transport(transportError.localizedDescription)
        }
    }

    func reset() {
        addresses = []
        source = ""
        error = nil
        isLoading = false
    }

    private func fetchSliceObjects(
        ctx: String,
        namespace: String,
        rows: [TablePayload.Row]
    ) async -> [JSONValue] {
        var objects: [JSONValue] = []
        for row in rows.prefix(10) {
            if let object = try? await KubeAPIClient.shared.getObject(
                ctx: ctx,
                ns: namespace,
                resource: "endpointslices.discovery.k8s.io",
                name: row.object.name
            ) {
                objects.append(object)
            }
        }
        return objects
    }
}
