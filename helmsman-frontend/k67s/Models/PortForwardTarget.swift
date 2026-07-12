import Foundation

/// A selectable port exposed in the Port Forward context-menu submenu.
struct PortForwardPortOption: Identifiable, Hashable, Sendable {
    let containerName: String?
    let port: Int
    let `protocol`: String

    var id: String { "\(containerName ?? ""):\(port):\(`protocol`)" }

    var label: String {
        if let containerName, !containerName.isEmpty {
            return "\(containerName): \(port)/\(`protocol`)"
        }
        if let name = servicePortName, !name.isEmpty {
            return "\(name): \(port)/\(`protocol`)"
        }
        return "\(port)/\(`protocol`)"
    }

    /// Service port name (e.g. `http`), when forwarding a Service.
    let servicePortName: String?

    init(containerName: String? = nil, servicePortName: String? = nil, port: Int, protocol: String = "TCP") {
        self.containerName = containerName
        self.servicePortName = servicePortName
        self.port = port
        self.protocol = `protocol`
    }

    /// Manual port entry when the object has no declared ports (or user wants another port).
    static let custom = PortForwardPortOption(
        containerName: nil,
        servicePortName: "custom",
        port: 0,
        protocol: "TCP"
    )

    var isCustom: Bool { port == 0 && servicePortName == "custom" }
}

/// Context for the Port Forward start sheet.
struct PortForwardTarget: Identifiable {
    let row: TablePayload.Row
    let ctx: String
    let resource: ResourceType
    let portOption: PortForwardPortOption

    var id: String { "\(row.id)-\(portOption.id)" }

    var namespaceName: String {
        let ns = row.object.namespace ?? ""
        return ns.isEmpty ? row.object.name : "\(ns)/\(row.object.name)"
    }

    var remoteLabelPrefix: String {
        switch resource.resource {
        case "pods": return "pod:"
        case "services": return "service:"
        default: return ":"
        }
    }

    var remoteLabel: String {
        if portOption.isCustom {
            return "\(remoteLabelPrefix)…"
        }
        return "\(remoteLabelPrefix)\(portOption.port)"
    }

    var suggestedLocalPort: String {
        portOption.isCustom ? "" : String(portOption.port)
    }

    var suggestedRemotePort: String {
        portOption.isCustom ? "" : String(portOption.port)
    }
}

/// Parses container and service ports from a Kubernetes object JSON.
enum PortForwardPortParser {
    static func podPorts(from object: JSONValue) -> [PortForwardPortOption] {
        var options: [PortForwardPortOption] = []
        let containers = object["spec"]?["containers"]?.arrayValue ?? []
        let initContainers = object["spec"]?["initContainers"]?.arrayValue ?? []
        for container in containers + initContainers {
            let name = container["name"]?.stringValue ?? ""
            for port in container["ports"]?.arrayValue ?? [] {
                guard let num = portNumber(from: port["containerPort"]) else { continue }
                let proto = port["protocol"]?.stringValue ?? "TCP"
                options.append(PortForwardPortOption(containerName: name, port: num, protocol: proto))
            }
        }
        return options
    }

    static func servicePorts(from object: JSONValue) -> [PortForwardPortOption] {
        var options: [PortForwardPortOption] = []
        for port in object["spec"]?["ports"]?.arrayValue ?? [] {
            guard let num = portNumber(from: port["port"]) else { continue }
            let proto = port["protocol"]?.stringValue ?? "TCP"
            let name = port["name"]?.stringValue
            options.append(PortForwardPortOption(servicePortName: name, port: num, protocol: proto))
        }
        return options
    }

    private static func portNumber(from value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .int(let n): return n
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
}
