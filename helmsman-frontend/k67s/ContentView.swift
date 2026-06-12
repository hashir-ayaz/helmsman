import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @State private var showError = false

    var body: some View {
        NavigationSplitView {
            SidebarView(app: app)
        } detail: {
            if let resource = app.selectedResource {
                ResourceListView(app: app, resource: resource)
            } else {
                ContentUnavailableView("Select a Resource", systemImage: "square.grid.2x2")
            }
        }
        .task {
            await app.bootstrap()
        }
        .onChange(of: app.globalError) { _, newValue in
            showError = newValue != nil
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("OK") { app.globalError = nil }
        } message: {
            Text(app.globalError?.errorDescription ?? "Unknown error")
        }
    }
}

#Preview {
    ContentView()
}
