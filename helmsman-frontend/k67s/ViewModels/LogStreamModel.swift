import SwiftUI

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// Streams one pod's logs into a bounded, filterable buffer.
@Observable
@MainActor
final class LogStreamModel {
    private(set) var lines: [LogLine] = []
    private(set) var isStreaming = false
    var error: APIError?
    var filterText = ""
    var follow = true
    var containers: [String] = []
    var selectedContainer: String? {
        didSet {
            if oldValue != selectedContainer { restart() }
        }
    }

    private let target: LogWindowTarget
    private let maxLines = 5_000
    private var nextID = 0
    private var streamTask: Task<Void, Never>?

    init(target: LogWindowTarget) {
        self.target = target
    }

    var filteredLines: [LogLine] {
        guard !filterText.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(filterText) }
    }

    func loadContainers() async {
        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: target.ctx, ns: target.namespace, resource: "pods", name: target.pod
            )
            let spec = object["spec"]
            let names = (spec?["containers"]?.arrayValue ?? [])
                .compactMap { $0["name"]?.stringValue }
            let initNames = (spec?["initContainers"]?.arrayValue ?? [])
                .compactMap { $0["name"]?.stringValue }
            containers = names + initNames
            if selectedContainer == nil { selectedContainer = containers.first }
        } catch {
            // Non-fatal: fall back to the server's default container.
        }
    }

    func start() {
        streamTask?.cancel()
        lines = []
        nextID = 0
        error = nil
        isStreaming = true
        let stream = KubeAPIClient.shared.streamLogs(
            ctx: target.ctx,
            ns: target.namespace,
            pod: target.pod,
            container: selectedContainer,
            follow: true,
            tailLines: 1_000,
            previous: target.previous
        )
        streamTask = Task { [weak self] in
            do {
                for try await line in stream {
                    guard let self else { return }
                    self.append(line)
                }
            } catch is CancellationError {
                // Expected on stop()/window close.
            } catch let apiError as APIError {
                self?.error = apiError
            } catch {
                self?.error = .transport(error.localizedDescription)
            }
            self?.isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        lines = []
    }

    func allText() -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    private func restart() {
        guard streamTask != nil || isStreaming || !lines.isEmpty else { return }
        start()
    }

    private func append(_ text: String) {
        lines.append(LogLine(id: nextID, text: text))
        nextID += 1
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
