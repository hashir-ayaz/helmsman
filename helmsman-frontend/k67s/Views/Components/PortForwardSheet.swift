import SwiftUI

/// Modal sheet for starting a port-forward session.
struct PortForwardSheet: View {
    @Bindable var actions: ResourceActionsModel
    let target: PortForwardTarget
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        guard !actions.isBusy else { return false }
        if target.portOption.isCustom {
            let remote = actions.portForwardRemotePortText.trimmingCharacters(in: .whitespaces)
            return Int(remote).map { $0 > 0 } ?? false
        }
        return true
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
            if actions.portForwardLocalPortText.isEmpty, !target.portOption.isCustom {
                actions.portForwardLocalPortText = target.suggestedLocalPort
            }
            if actions.portForwardRemotePortText.isEmpty {
                actions.portForwardRemotePortText = target.suggestedRemotePort
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
                if target.portOption.isCustom {
                    Text(target.remoteLabelPrefix)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    TextField("Port", text: $actions.portForwardRemotePortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                } else {
                    Text(target.remoteLabel)
                        .font(.body.monospaced())
                }
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
