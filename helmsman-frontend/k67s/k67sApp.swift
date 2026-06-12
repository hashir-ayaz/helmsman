import SwiftUI

@main
struct k67sApp: App {
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
    }
}
