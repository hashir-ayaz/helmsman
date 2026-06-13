import SwiftUI
import AppKit
import SwiftTerm

// MARK: - Terminal surface (NSViewRepresentable)

/// Wraps LocalProcessTerminalView. Recreated entirely by SwiftUI when restartToken changes
/// (caller uses .id(model.restartToken)). On creation it calls startProcess immediately.
private struct TerminalSurface: NSViewRepresentable {
    let executable: String
    let args: [String]
    let env: [String]
    let onStart: @MainActor () -> Void
    let onTerminate: @MainActor (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStart: onStart, onTerminate: onTerminate) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: .zero)
        tv.processDelegate = context.coordinator
        context.coordinator.terminalView = tv
        // Slight delay so the view has a chance to be laid out before the process starts.
        // (Without this, startProcess can be called before the view has a valid frame.)
        DispatchQueue.main.async {
            tv.startProcess(executable: self.executable, args: self.args, environment: self.env)
            self.onStart()
        }
        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // restartToken changes cause SwiftUI to destroy+recreate this view via .id(),
        // so updateNSView only needs to handle live layout changes — nothing else.
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onStart: @MainActor () -> Void
        let onTerminate: @MainActor (Int32?) -> Void
        weak var terminalView: LocalProcessTerminalView?

        init(onStart: @escaping @MainActor () -> Void, onTerminate: @escaping @MainActor (Int32?) -> Void) {
            self.onStart = onStart
            self.onTerminate = onTerminate
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { self.onTerminate(exitCode) }
        }
    }
}

// MARK: - ShellWindowView

struct ShellWindowView: View {
    let target: ShellWindowTarget
    @State private var model: ShellSessionModel

    init(target: ShellWindowTarget) {
        self.target = target
        _model = State(initialValue: ShellSessionModel(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            shellBody
            Divider()
            bottomBar
        }
        .navigationTitle(target.windowTitle)
        .toolbar { toolbarContent }
        .task { await model.loadContainers() }
    }

    // MARK: - Main body

    @ViewBuilder
    private var shellBody: some View {
        if model.kubectlMissing {
            // kubectl not installed — show friendly error
            ContentUnavailableView {
                Label("kubectl Not Found", systemImage: "terminal")
            } description: {
                Text("Install kubectl to use the shell feature.\n`brew install kubectl`")
            }
        } else if let params = model.launchParams() {
            TerminalSurface(
                executable: params.executable,
                args: params.args,
                env: params.env,
                onStart: { model.processDidStart() },
                onTerminate: { code in model.processDidTerminate(code: code) }
            )
            .id(model.restartToken)   // key: forces recreation on container switch / restart
        } else {
            // kubectl resolved but container list still loading
            ProgressView()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            if model.isRunning {
                Text("Connected")
                    .foregroundStyle(.secondary)
            } else if let code = model.exitCode {
                Text("Exited (\(code))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Connecting…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if model.containers.count > 1 {
                Picker("Container", selection: $model.selectedContainer) {
                    ForEach(model.containers, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            Button {
                model.restart()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Restart shell")
        }
    }
}
