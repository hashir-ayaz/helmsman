import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch app.connectionPhase {
            case .connecting:
                BootstrapGateView(phase: .connecting(step: app.bootstrapStep))
            case .failed(let title, let message, let code):
                BootstrapGateView(phase: .failed(title: title, message: message, code: code)) {
                    Task { await app.retryConnection() }
                }
            case .ready:
                mainView
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .animation(reduceMotion ? nil : HelmsmanMotion.gate, value: app.connectionPhase)
        .task {
            await app.bootstrap()
        }
    }

    private var mainView: some View {
        NavigationSplitView {
            SidebarView(app: app)
        } detail: {
            switch app.selectedDestination {
            case .overview:
                ClusterOverviewView(app: app)
            case .resource(let resource):
                ResourceListView(app: app, resource: resource)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

#Preview {
    ContentView()
}
