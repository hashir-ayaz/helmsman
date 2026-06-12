import Darwin
import Foundation
import OSLog

/// Manages the embedded Go backend (`helmsman-api`) as a child process.
///
/// In a packaged build the universal `helmsman-api` binary lives in the app
/// bundle's `Contents/Resources`. On launch we pick a free localhost port, point
/// `KubeAPIClient` at it, and spawn the backend with that `PORT`. The child's
/// `stdin` is wired to a pipe we hold open so the backend can detect our death
/// (see `watchParentDeath` in the Go server) and exit instead of orphaning.
///
/// When the binary is *not* bundled (i.e. running from Xcode during
/// development), we no-op and leave `KubeAPIClient.baseURL` at its default so the
/// app talks to a server started manually via `make run`.
@MainActor
final class BackendProcess {
    static let shared = BackendProcess()

    private let log = Logger(subsystem: "hashir-ayaz.k67s", category: "backend")
    private var process: Process?
    /// Retained for the process's lifetime: closing it signals EOF to the child.
    private var stdinPipe: Pipe?

    private init() {}

    /// Starts the embedded backend if it is bundled. Safe to call once at launch.
    func start() {
        guard process == nil else { return }

        guard let binary = Bundle.main.url(forResource: "helmsman-api", withExtension: nil) else {
            log.notice("No embedded helmsman-api binary; expecting a backend on \(KubeAPIClient.baseURL, privacy: .public) (dev mode).")
            return
        }

        let port = Self.freePort()
        KubeAPIClient.configure(port: port)

        let proc = Process()
        proc.executableURL = binary
        proc.environment = childEnvironment(port: port)

        let stdin = Pipe()
        proc.standardInput = stdin
        self.stdinPipe = stdin

        // Surface backend logs in the unified log for debugging.
        let output = Pipe()
        proc.standardOutput = output
        proc.standardError = output
        output.fileHandleForReading.readabilityHandler = { [log] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            log.debug("\(text, privacy: .public)")
        }

        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.log.notice("backend exited with status \(proc.terminationStatus)")
                self?.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
            log.notice("started embedded backend on port \(port) (pid \(proc.processIdentifier))")
        } catch {
            log.error("failed to start backend: \(error.localizedDescription, privacy: .public)")
            stdinPipe = nil
            process = nil
        }
    }

    /// Terminates the backend. Call from `applicationWillTerminate`.
    func stop() {
        guard let proc = process else { return }
        process = nil
        stdinPipe?.fileHandleForWriting.closeFile() // EOF → backend's parent-death watchdog fires
        stdinPipe = nil
        proc.terminate()
    }

    /// Builds the child environment: inherit the user's, force `PORT`, enable the
    /// parent-death watchdog, and widen `PATH`. GUI apps launched from Finder get
    /// a minimal `PATH`, so kubeconfig exec credential plugins (`aws`,
    /// `gke-gcloud-auth-plugin`, `kubelogin`, …) installed in Homebrew/krew paths
    /// would otherwise be unreachable.
    private func childEnvironment(port: Int) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["HELMSMAN_PARENT_WATCH"] = "1"

        let home = NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.krew/bin",
            "\(home)/bin",
        ]
        let existing = env["PATH"].map { [$0] } ?? []
        env["PATH"] = (extras + existing).joined(separator: ":")
        return env
    }

    /// Asks the kernel for an unused localhost TCP port by binding to port 0.
    /// Falls back to 8080 on the (unexpected) failure path.
    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 8080 }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 8080 }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard named == 0 else { return 8080 }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
