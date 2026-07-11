import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()

    var body: some View {
        Group {
            switch app.connectionPhase {
            case .connecting:
                connectingView
            case .failed(let title, let message, _):
                failedView(title: title, message: message)
            case .ready:
                mainView
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            await app.bootstrap()
        }
    }

    private var mainView: some View {
        NavigationSplitView {
            SidebarView(app: app)
        } detail: {
            if let resource = app.selectedResource {
                ResourceListView(app: app, resource: resource)
            } else {
                ContentUnavailableView("Select a Resource", systemImage: "square.grid.2x2")
            }
        }
    }

    private var connectingView: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
        } description: {
            Text("Connecting to your cluster")
                .font(.title3)
        } actions: {
            Text("Starting the Helmsman backend and loading your kubeconfig.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }

    private func failedView(title: String, message: String) -> some View {
        ContentUnavailableView {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
        } description: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        } actions: {
            Button("Retry") {
                Task { await app.retryConnection() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    ContentView()
}
