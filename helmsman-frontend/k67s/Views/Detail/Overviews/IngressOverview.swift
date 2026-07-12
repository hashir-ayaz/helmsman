import SwiftUI

/// Parsed Ingress backend for relationship navigation.
struct IngressBackend: Identifiable, Hashable {
    let id: String
    let host: String
    let path: String
    let serviceName: String
    let servicePort: String
}

enum IngressBackendParser {
    static func backends(from object: JSONValue) -> [IngressBackend] {
        var result: [IngressBackend] = []
        let rules = object["spec"]?["rules"]?.arrayValue ?? []
        for (ruleIndex, rule) in rules.enumerated() {
            let host = rule["host"]?.stringValue ?? "*"
            let paths = rule["http"]?["paths"]?.arrayValue ?? []
            for (pathIndex, path) in paths.enumerated() {
                guard let serviceName = path["backend"]?["service"]?["name"]?.stringValue,
                      !serviceName.isEmpty else { continue }
                let portNumber = path["backend"]?["service"]?["port"]?["number"]?.displayString
                let portName = path["backend"]?["service"]?["port"]?["name"]?.stringValue
                let port = portNumber ?? portName ?? "?"
                let pathValue = path["path"]?.stringValue ?? "/"
                result.append(IngressBackend(
                    id: "\(ruleIndex)-\(pathIndex)-\(serviceName)-\(port)",
                    host: host,
                    path: pathValue,
                    serviceName: serviceName,
                    servicePort: port
                ))
            }
        }
        if let defaultBackend = object["spec"]?["defaultBackend"]?["service"] {
            let serviceName = defaultBackend["name"]?.stringValue ?? ""
            if !serviceName.isEmpty {
                let portNumber = defaultBackend["port"]?["number"]?.displayString
                let portName = defaultBackend["port"]?["name"]?.stringValue
                let port = portNumber ?? portName ?? "?"
                result.append(IngressBackend(
                    id: "default-\(serviceName)-\(port)",
                    host: "*",
                    path: "/",
                    serviceName: serviceName,
                    servicePort: port
                ))
            }
        }
        return result
    }
}

struct IngressOverview: View {
    let object: JSONValue
    var namespace: String?
    var onSelectService: ((TablePayload.Row) -> Void)?

    private var backends: [IngressBackend] {
        IngressBackendParser.backends(from: object)
    }

    private var effectiveNamespace: String? {
        namespace ?? object["metadata"]?["namespace"]?.stringValue
    }

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let className = object["spec"]?["ingressClassName"]?.stringValue {
                    DetailRow(label: "Ingress Class", value: className)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                if let loadBalancer = loadBalancerHosts, !loadBalancer.isEmpty {
                    DetailRow(label: "Address", value: loadBalancer)
                }
            }
        }

        if !backends.isEmpty {
            DetailSection(title: "Backends") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(backends) { backend in
                        Button {
                            guard let ns = effectiveNamespace else { return }
                            onSelectService?(.stub(name: backend.serviceName, namespace: ns))
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backend.serviceName)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text("\(backend.host)\(backend.path) → :\(backend.servicePort)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .disabled(onSelectService == nil)

                        if backend.id != backends.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } else {
            DetailSection(title: "Backends") {
                Text("No backend services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadBalancerHosts: String? {
        let entries = object["status"]?["loadBalancer"]?["ingress"]?.arrayValue ?? []
        let hosts = entries.compactMap { entry -> String? in
            if let ip = entry["ip"]?.stringValue, !ip.isEmpty { return ip }
            if let hostname = entry["hostname"]?.stringValue, !hostname.isEmpty { return hostname }
            return nil
        }
        guard !hosts.isEmpty else { return nil }
        return hosts.joined(separator: ", ")
    }
}
