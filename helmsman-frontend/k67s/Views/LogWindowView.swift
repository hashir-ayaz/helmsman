import SwiftUI
import AppKit

struct LogWindowView: View {
    let target: LogWindowTarget
    @State private var model: LogStreamModel

    init(target: LogWindowTarget) {
        self.target = target
        _model = State(initialValue: LogStreamModel(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            logBody
            Divider()
            bottomBar
        }
        .navigationTitle(target.windowTitle)
        .toolbar { toolbarContent }
        .task {
            await model.resolveJobPodsIfNeeded()
            guard model.canStream else { return }
            await model.loadContainers()
            model.start()
        }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var logBody: some View {
        if let error = model.error, model.lines.isEmpty, !model.canStream {
            ErrorStateView(error: error) {
                Task {
                    await model.resolveJobPodsIfNeeded()
                    guard model.canStream else { return }
                    await model.loadContainers()
                    model.start()
                }
            }
        } else if let error = model.error, model.lines.isEmpty {
            ErrorStateView(error: error) { model.start() }
        } else {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.filteredLines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.lines.count) {
                    guard model.follow else { return }
                    withAnimation(.none) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Filter logs", text: $model.filterText)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(model.isStreaming ? .green : .secondary)
                    .frame(width: 7, height: 7)
                Text(model.isStreaming ? "Live" : "Stopped")
                    .foregroundStyle(.secondary)
                Text("\(model.filteredLines.count) lines")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if !model.jobPods.isEmpty {
                Picker("Pod", selection: $model.selectedPod) {
                    ForEach(model.jobPods, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            if model.containers.count > 1 {
                Picker("Container", selection: $model.selectedContainer) {
                    ForEach(model.containers, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            Toggle(isOn: $model.follow) {
                Label("Follow", systemImage: "arrow.down.to.line")
            }
            .help("Auto-scroll to the latest line")

            Button {
                model.clear()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear")

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(model.allText(), forType: .string)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Copy all logs")
        }
    }

    private let bottomAnchor = "logs.bottom.anchor"
}
