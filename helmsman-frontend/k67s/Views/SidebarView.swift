import SwiftUI

struct SidebarView: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            pickers
            Divider()
            List(selection: $app.selectedResource) {
                ForEach(ResourceSection.allCases, id: \.self) { section in
                    let items = ResourceType.all.filter { $0.section == section }
                    if !items.isEmpty {
                        Section(section.rawValue) {
                            ForEach(items) { resource in
                                Label(resource.title, systemImage: resource.symbol)
                                    .tag(resource)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 215)
    }

    private var pickers: some View {
        VStack(spacing: 6) {
            Picker("Context", selection: $app.selectedContext) {
                Text("Current Context").tag("_current")
                ForEach(app.contexts) { context in
                    Text(context.name).tag(context.name)
                }
            }
            .labelsHidden()

            Picker("Namespace", selection: $app.selectedNamespace) {
                ForEach(app.namespacePickerOptions, id: \.self) { namespace in
                    Text(namespace).tag(namespace)
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}
