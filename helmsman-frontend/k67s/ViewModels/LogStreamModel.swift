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
    private(set) var jobPods: [String] = []
    var error: APIError?
    var filterText = ""
    var follow = true
    var containers: [String] = []
    var selectedPod: String? {
        didSet {
            guard oldValue != selectedPod, target.job != nil, selectedPod != nil else { return }
            Task { await switchPod() }
        }
    }
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
        self.selectedPod = target.pod
    }

    var filteredLines: [LogLine] {
        guard !filterText.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(filterText) }
    }

    var canStream: Bool {
        activePod != nil
    }

    /// Lists Job-owned pods and picks a default pod to stream.
    func resolveJobPodsIfNeeded() async {
        guard let job = target.job else { return }
        do {
            let table = try await KubeAPIClient.shared.listResources(
                ctx: target.ctx,
                ns: target.namespace,
                resource: "pods",
                labelSelector: "job-name=\(job)"
            )
            jobPods = sortedPodNames(from: table)
            if jobPods.isEmpty {
                error = .transport("No pods found for this Job.")
                selectedPod = nil
                return
            }
            if selectedPod == nil || !jobPods.contains(selectedPod!) {
                selectedPod = jobPods.first
            }
        } catch let apiError as APIError {
            self.error = apiError
            selectedPod = nil
        } catch {
            self.error = .transport(error.localizedDescription)
            selectedPod = nil
        }
    }

    func loadContainers() async {
        guard let pod = activePod else { return }
        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: target.ctx, ns: target.namespace, resource: "pods", name: pod
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
        guard let pod = activePod else {
            isStreaming = false
            return
        }
        streamTask?.cancel()
        lines = []
        nextID = 0
        error = nil
        isStreaming = true
        let stream = KubeAPIClient.shared.streamLogs(
            ctx: target.ctx,
            ns: target.namespace,
            pod: pod,
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

    private var activePod: String? {
        selectedPod ?? target.pod
    }

    private func switchPod() async {
        selectedContainer = nil
        containers = []
        await loadContainers()
        start()
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

    /// Newest pods first — prefer the Age column when present, else reverse name order.
    private func sortedPodNames(from table: TablePayload) -> [String] {
        let ageIndex = table.columns.firstIndex { $0.name.lowercased() == "age" }
        if let ageIndex {
            return table.rows
                .sorted { lhs, rhs in
                    let left = lhs.cells[safe: ageIndex]?.displayString ?? ""
                    let right = rhs.cells[safe: ageIndex]?.displayString ?? ""
                    return ageDuration(left) < ageDuration(right)
                }
                .map(\.object.name)
        }
        return table.rows.map(\.object.name).sorted().reversed()
    }

    /// Rough ordering for kubectl Age strings (smaller = newer).
    private func ageDuration(_ age: String) -> Int {
        let trimmed = age.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("s"), let value = Int(trimmed.dropLast()) { return value }
        if trimmed.hasSuffix("m"), let value = Int(trimmed.dropLast()) { return value * 60 }
        if trimmed.hasSuffix("h"), let value = Int(trimmed.dropLast()) { return value * 3_600 }
        if trimmed.hasSuffix("d"), let value = Int(trimmed.dropLast()) { return value * 86_400 }
        return Int.max
    }
}
