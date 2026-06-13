import Foundation
import SwiftUI

@Observable
@MainActor
final class ShellSessionModel {

    // MARK: - Container list

    private(set) var containers: [String] = []
    var selectedContainer: String? {
        didSet {
            if oldValue != selectedContainer { bumpRestartToken() }
        }
    }

    // MARK: - Shell process status

    private(set) var isRunning = false
    private(set) var exitCode: Int32?

    // MARK: - kubectl availability

    private(set) var kubectlMissing = false
    private(set) var kubectlPath: String?

    // MARK: - Restart token

    /// Bumped when the container changes or the user hits Restart.
    /// The View binds `.id(restartToken)` to force SwiftUI to recreate the terminal view.
    private(set) var restartToken = 0

    // MARK: - Private state

    private let target: ShellWindowTarget

    // MARK: - Init

    init(target: ShellWindowTarget) {
        self.target = target
    }

    // MARK: - Container discovery

    func loadContainers() async {
        resolveKubectl()

        do {
            let object = try await KubeAPIClient.shared.getObject(
                ctx: target.ctx,
                ns: target.namespace,
                resource: "pods",
                name: target.pod
            )
            let spec = object["spec"]
            let names = (spec?["containers"]?.arrayValue ?? [])
                .compactMap { $0["name"]?.stringValue }
            let initNames = (spec?["initContainers"]?.arrayValue ?? [])
                .compactMap { $0["name"]?.stringValue }
            containers = names + initNames
            if selectedContainer == nil { selectedContainer = containers.first }
        } catch {
            // Non-fatal — container list remains empty
        }
    }

    // MARK: - kubectl resolution

    func resolveKubectl() {
        let home = NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.krew/bin",
            "\(home)/bin"
        ]
        let existing = ProcessInfo.processInfo.environment["PATH"]
            .map { $0.split(separator: ":").map(String.init) } ?? []
        let searchDirs = extras + existing

        for dir in searchDirs {
            let candidate = "\(dir)/kubectl"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                kubectlPath = candidate
                kubectlMissing = false
                return
            }
        }

        kubectlMissing = true
    }

    // MARK: - Launch parameters

    /// Returns `(executablePath, args, envArray)` ready for process launch,
    /// or `nil` if `kubectl` was not found on PATH.
    func launchParams() -> (executable: String, args: [String], env: [String])? {
        guard let kubectl = kubectlPath else { return nil }

        var args = ["exec", "-it"]
        if target.ctx != "_current" {
            args += ["--context", target.ctx]
        }
        args += ["-n", target.namespace, target.pod]
        if let container = selectedContainer {
            args += ["-c", container]
        }
        args += ["--", "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"]

        var envDict = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.krew/bin",
            "\(home)/bin"
        ]
        let existing = envDict["PATH"].map { [$0] } ?? []
        envDict["PATH"] = (extras + existing).joined(separator: ":")
        let envArray = envDict.map { "\($0.key)=\($0.value)" }

        return (kubectl, args, envArray)
    }

    // MARK: - Status callbacks (called by the terminal view's delegate)

    func processDidStart() {
        isRunning = true
        exitCode = nil
    }

    func processDidTerminate(code: Int32?) {
        isRunning = false
        exitCode = code
    }

    // MARK: - Manual restart

    func restart() {
        bumpRestartToken()
    }

    // MARK: - Private

    private func bumpRestartToken() {
        restartToken += 1
        isRunning = false
        exitCode = nil
    }
}
