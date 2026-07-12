import SwiftUI

/// Modal sheet for starting a port-forward session.
struct PortForwardSheet: View {
    @Bindable var actions: ResourceActionsModel
    let target: PortForwardTarget
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !actions.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 420)
        .padding(.top, 4)
        .onAppear {
            if actions.portForwardLocalPortText.isEmpty {
                actions.portForwardLocalPortText = target.suggestedLocalPort
            }
            actions.portForwardOpenInBrowser = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Port Forward")
                .font(.title3.weight(.semibold))
            Text(target.namespaceName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("localhost:")
                    .foregroundStyle(.secondary)
                TextField("Port", text: $actions.portForwardLocalPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                Text("→")
                    .foregroundStyle(.secondary)
                Text(target.remoteLabel)
                    .font(.body.monospaced())
            }

            Toggle("Open in browser when ready", isOn: $actions.portForwardOpenInBrowser)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) {
                actions.portForwardTarget = nil
                dismiss()
            }
            Button("Start") {
                let captured = target
                Task { await actions.performPortForward(captured) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(20)
    }
}
