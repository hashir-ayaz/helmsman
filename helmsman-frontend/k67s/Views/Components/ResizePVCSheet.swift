import SwiftUI

/// Modal sheet for increasing a PVC's storage request.
struct ResizePVCSheet: View {
    @Bindable var actions: ResourceActionsModel
    let target: ResizePVCTarget
    @Environment(\.dismiss) private var dismiss

    private var newRequest: String {
        let value = actions.resizeValueText.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return "—" }
        return "\(value)\(actions.resizeUnit.rawValue)"
    }

    private var canSubmit: Bool {
        let value = actions.resizeValueText.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, Double(value) != nil else { return false }
        return !actions.isBusy
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resize PVC")
                .font(.title3.weight(.semibold))
            Text(target.namespaceName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(label: "Current request", value: target.currentRequest)
            infoRow(label: "Capacity", value: target.capacity)
            infoRow(label: "StorageClass", value: target.storageClass)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Size", text: $actions.resizeValueText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Picker("Unit", selection: $actions.resizeUnit) {
                    ForEach(PVCResizeUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 72)
            }

            Text("New request: \(newRequest)")
                .font(.callout)
                .foregroundStyle(.secondary)

            if showsShrinkHint {
                Text("New request should be larger than the current request.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Kubernetes volume expansion may take time and depends on the StorageClass.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                actions.resizeTarget = nil
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Resize") {
                let captured = target
                Task {
                    await actions.performResize(captured)
                    if actions.resizeTarget == nil {
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(16)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private var showsShrinkHint: Bool {
        guard let newValue = Double(actions.resizeValueText.trimmingCharacters(in: .whitespaces)),
              let currentValue = Double(ResizePVCTarget.parseQuantity(target.currentRequest).value)
        else { return false }
        return newValue <= currentValue
            && actions.resizeUnit == PVCResizeUnit(rawValue: ResizePVCTarget.parseQuantity(target.currentRequest).unit)
    }
}
