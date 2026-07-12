import SwiftUI

/// Cascade policy for Kubernetes delete operations.
enum DeletePropagationPolicy: String, CaseIterable, Identifiable, Sendable {
    case background = "Background"
    case foreground = "Foreground"
    case orphan = "Orphan"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .background:
            "Delete the parent now; dependents are cleaned up asynchronously (Kubernetes default)."
        case .foreground:
            "Wait for all dependents to be deleted before removing the parent (ordered teardown)."
        case .orphan:
            "Delete the parent and leave dependents running without an owner."
        }
    }
}

/// Modal sheet for deleting a controller with explicit cascade options.
struct DeleteOptionsSheet: View {
    @Bindable var actions: ResourceActionsModel
    let row: TablePayload.Row
    @Environment(\.dismiss) private var dismiss

    private var resourceName: String { row.object.name }

    private var canSubmit: Bool { !actions.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 460)
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Delete with Options")
                .font(.title3.weight(.semibold))
            Text(resourceName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Cascade", selection: $actions.deletePropagationPolicy) {
                ForEach(DeletePropagationPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.radioGroup)

            Text(actions.deletePropagationPolicy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Immediate (grace period 0)", isOn: $actions.deleteImmediate)
                .toggleStyle(.checkbox)

            if actions.deletePropagationPolicy == .orphan {
                Text("Dependent pods and other owned resources will keep running without an owner.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if actions.deleteImmediate {
                Text("Does not remove finalizers. Objects with blocking finalizers may stay Terminating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                actions.deleteOptionsTarget = nil
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Delete", role: .destructive) {
                let captured = row
                Task {
                    await actions.performDeleteWithOptions(captured)
                    if actions.deleteOptionsTarget == nil {
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(16)
    }
}
