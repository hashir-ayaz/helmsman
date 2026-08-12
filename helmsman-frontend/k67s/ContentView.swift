import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @State private var onboarding = OnboardingModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !onboarding.isComplete {
                OnboardingView(model: onboarding)
            } else {
                connectionContent
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .animation(reduceMotion ? nil : HelmsmanMotion.gate, value: onboarding.isComplete)
        .animation(reduceMotion ? nil : HelmsmanMotion.gate, value: app.connectionPhase)
        .task {
            await app.bootstrap()
        }
    }

    @ViewBuilder
    private var connectionContent: some View {
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

    private var mainView: some View {
        NavigationSplitView {
            SidebarView(app: app)
        } detail: {
            switch app.selectedDestination {
            case .overview:
                ClusterOverviewView(app: app)
                    .id("overview")
            case .portForwards:
                PortForwardsView(app: app, model: app.portForwards)
                    .id("portforwards")
            case .resource(let resource):
                // Remount per resource so @State (payload/columns) never carries
                // across list switches — TableColumnForEach crashes on empty↔N column diffs.
                ResourceListView(app: app, resource: resource)
                    .id(resource.id)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

#Preview {
    ContentView()
}
