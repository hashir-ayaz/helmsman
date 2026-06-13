import AppKit
import SwiftUI

@main
struct k67sApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        WindowGroup(id: "logs", for: LogWindowTarget.self) { $target in
            if let target {
                LogWindowView(target: target)
            }
        }
        .defaultSize(width: 900, height: 560)

        WindowGroup(id: "yaml", for: YAMLWindowTarget.self) { $target in
            if let target {
                YAMLEditorWindow(target: target)
            }
        }
        .defaultSize(width: 820, height: 680)

        WindowGroup(id: "shell", for: ShellWindowTarget.self) { $target in
            if let target {
                ShellWindowView(target: target)
            }
        }
        .defaultSize(width: 820, height: 520)
    }
}

/// Owns the embedded backend lifecycle: starts the bundled `helmsman-api`
/// sidecar at launch and tears it down on quit so no server is left orphaned.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BackendProcess.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        BackendProcess.shared.stop()
    }
}
