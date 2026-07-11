import Foundation

/// Generic client for the dynamic Kubernetes backend. Every method is keyed on
/// the resource type in the URL — no per-resource code. `ctx` defaults to
/// `_current` (the active kubeconfig context).
actor KubeAPIClient {
    static let shared = KubeAPIClient()

    /// Base URL of the local backend. Written once at launch by `BackendProcess`
    /// (which picks a free port for the embedded sidecar) before any request is
    /// issued, and otherwise defaults to the standalone `make run` port. Marked
    /// `nonisolated(unsafe)` because `streamLogs` reads it from a nonisolated
    /// context; the only write happens at startup, before UI traffic begins.
    nonisolated(unsafe) static var baseURL = "http://127.0.0.1:8080"

    /// Points the client at a specific backend port. Call before issuing requests.
    static func configure(port: Int) {
        baseURL = "http://127.0.0.1:\(port)"
    }

    private let decoder = JSONDecoder()
    private let session = URLSession.shared

    // MARK: - Read API

    /// Liveness probe — succeeds when the HTTP server is accepting connections.
    func checkHealth() async throws {
        guard let url = URL(string: Self.baseURL + "/health") else { throw APIError.invalidURL }
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    /// Cluster readiness — kubeconfig loaded and contexts available.
    func fetchStatus() async throws -> ClusterStatus {
        try await getEnveloped("/api/v1/status")
    }

    func listContexts() async throws -> [ContextInfo] {
        try await getEnveloped("/api/v1/contexts")
    }

    func listResources(
        ctx: String = "_current",
        ns: String?,
        resource: String,
        labelSelector: String? = nil,
        fieldSelector: String? = nil
    ) async throws -> TablePayload {
        var query: [URLQueryItem] = []
        if let labelSelector {
            query.append(URLQueryItem(name: "labelSelector", value: labelSelector))
        }
        if let fieldSelector {
            query.append(URLQueryItem(name: "fieldSelector", value: fieldSelector))
        }
        return try await getEnveloped(listPath(ctx: ctx, ns: ns, resource: resource), query: query)
    }

    func getObject(
        ctx: String = "_current",
        ns: String?,
        resource: String,
        name: String
    ) async throws -> JSONValue {
        try await getEnveloped(objectPath(ctx: ctx, ns: ns, resource: resource, name: name))
    }

    /// Raw YAML text — bypasses the JSON envelope (`Content-Type: application/yaml`).
    func getYAML(
        ctx: String = "_current",
        ns: String?,
        resource: String,
        name: String
    ) async throws -> String {
        let path = objectPath(ctx: ctx, ns: ns, resource: resource, name: name) + "/yaml"
        guard let url = makeURL(path, query: []) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/yaml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            try checkStatus(response, data: data)
            return String(decoding: data, as: UTF8.self)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    // MARK: - Mutations

    /// Server-side apply of a raw YAML/JSON manifest. Namespace is inferred from
    /// the manifest's `metadata.namespace`.
    @discardableResult
    func apply(ctx: String = "_current", yaml: String) async throws -> JSONValue {
        try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/resources",
            contentType: "text/plain",
            body: Data(yaml.utf8)
        )
    }

    func delete(ctx: String = "_current", ns: String, resource: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "DELETE",
            path: objectPath(ctx: ctx, ns: ns, resource: resource, name: name)
        )
    }

    func scale(ctx: String = "_current", ns: String, workload: String = "deployments", name: String, replicas: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["replicas": replicas])
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/scale",
            contentType: "application/json",
            body: body
        )
    }

    func restart(ctx: String = "_current", ns: String, workload: String, name: String, restartedAt: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["restartedAt": restartedAt])
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/restart",
            contentType: "application/json",
            body: body
        )
    }

    // MARK: - Rollout operations

    func rolloutPause(ctx: String = "_current", ns: String, workload: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/rollout/pause"
        )
    }

    func rolloutResume(ctx: String = "_current", ns: String, workload: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/rollout/resume"
        )
    }

    func getRolloutHistory(ctx: String = "_current", ns: String, workload: String, name: String) async throws -> [RevisionEntry] {
        try await getEnveloped("/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/rollout/history")
    }

    func rolloutUndo(ctx: String = "_current", ns: String, workload: String, name: String, toRevision: Int64 = 0) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["toRevision": toRevision])
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/rollout/undo",
            contentType: "application/json",
            body: body
        )
    }

    // MARK: - Suspend / Resume

    func suspend(ctx: String = "_current", ns: String, workload: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/suspend"
        )
    }

    func resume(ctx: String = "_current", ns: String, workload: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/\(enc(workload))/\(enc(name))/resume"
        )
    }

    // MARK: - Job cancel

    func cancelJob(ctx: String = "_current", ns: String, name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/jobs/\(enc(name))/cancel"
        )
    }

    // MARK: - Node drain

    func drainNode(ctx: String = "_current", name: String) async throws {
        let _: JSONValue = try await sendEnveloped(
            method: "POST",
            path: "/api/v1/contexts/\(enc(ctx))/nodes/\(enc(name))/drain"
        )
    }

    // MARK: - Log streaming (SSE)

    /// Streams a pod's logs as individual lines. Long-lived and `nonisolated` so
    /// it doesn't hop the actor per line. Frames arrive as `data: <line>` over
    /// `text/event-stream`; cancel the consuming task (or close the window) to stop.
    nonisolated func streamLogs(
        ctx: String = "_current",
        ns: String,
        pod: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        previous: Bool
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func encode(_ segment: String) -> String {
                    segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
                }
                let path = "/api/v1/contexts/\(encode(ctx))/namespaces/\(encode(ns))/pods/\(encode(pod))/log"
                var components = URLComponents(string: Self.baseURL + path)
                var query: [URLQueryItem] = []
                if let container, !container.isEmpty {
                    query.append(URLQueryItem(name: "container", value: container))
                }
                if follow { query.append(URLQueryItem(name: "follow", value: "true")) }
                if previous { query.append(URLQueryItem(name: "previous", value: "true")) }
                if let tailLines { query.append(URLQueryItem(name: "tailLines", value: String(tailLines))) }
                components?.queryItems = query

                guard let url = components?.url else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = .infinity
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw APIError.from(status: http.statusCode, message: "")
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            continuation.yield(String(line.dropFirst(6)))
                        } else if line.hasPrefix("data:") {
                            continuation.yield(String(line.dropFirst(5)))
                        }
                        // Ignore blank separators and other SSE fields.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams watch events for a resource type. Long-lived SSE; nonisolated for
    /// the same reason as `streamLogs` — it never hops the actor per event.
    nonisolated func streamWatch(
        ctx: String = "_current",
        ns: String?,
        resource: String
    ) -> AsyncThrowingStream<WatchEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func enc(_ s: String) -> String {
                    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
                }
                let path: String
                if let ns, !ns.isEmpty {
                    path = "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/resources/\(enc(resource))/watch"
                } else {
                    path = "/api/v1/contexts/\(enc(ctx))/resources/\(enc(resource))/watch"
                }
                guard let url = URL(string: Self.baseURL + path) else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = .infinity
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw APIError.from(status: http.statusCode, message: "")
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            guard let data = json.data(using: .utf8),
                                  let event = try? decoder.decode(WatchEvent.self, from: data)
                            else { continue }
                            continuation.yield(event)
                        } else if line.hasPrefix("data:") {
                            let json = String(line.dropFirst(5))
                            guard let data = json.data(using: .utf8),
                                  let event = try? decoder.decode(WatchEvent.self, from: data)
                            else { continue }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - URL building

    private func listPath(ctx: String, ns: String?, resource: String) -> String {
        if let ns, !ns.isEmpty {
            "/api/v1/contexts/\(enc(ctx))/namespaces/\(enc(ns))/resources/\(enc(resource))"
        } else {
            "/api/v1/contexts/\(enc(ctx))/resources/\(enc(resource))"
        }
    }

    private func objectPath(ctx: String, ns: String?, resource: String, name: String) -> String {
        listPath(ctx: ctx, ns: ns, resource: resource) + "/\(enc(name))"
    }

    private func enc(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }

    private func makeURL(_ path: String, query: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: Self.baseURL + path)
        if !query.isEmpty { components?.queryItems = query }
        return components?.url
    }

    // MARK: - Request execution

    private func getEnveloped<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let url = makeURL(path, query: query) else { throw APIError.invalidURL }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        try checkStatus(response, data: data)
        do {
            let envelope = try decoder.decode(APIResponse<T>.self, from: data)
            if let message = envelope.error { throw APIError.server(message) }
            guard let value = envelope.data else { throw APIError.invalidResponse }
            return value
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// Executes a method with an optional body and decodes the enveloped `data`.
    private func sendEnveloped<T: Decodable>(
        method: String,
        path: String,
        contentType: String? = nil,
        body: Data? = nil
    ) async throws -> T {
        guard let url = makeURL(path, query: []) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        try checkStatus(response, data: data)
        do {
            let envelope = try decoder.decode(APIResponse<T>.self, from: data)
            if let message = envelope.error { throw APIError.server(message) }
            guard let value = envelope.data else { throw APIError.invalidResponse }
            return value
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// Throws a mapped `APIError` for any non-2xx status, extracting the envelope
    /// `error` message when present.
    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        let message = (try? decoder.decode(APIResponse<JSONValue>.self, from: data))?.error
            ?? String(decoding: data, as: UTF8.self)
        throw APIError.from(status: http.statusCode, message: message)
    }
}
