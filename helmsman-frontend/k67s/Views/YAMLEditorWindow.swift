import SwiftUI

struct YAMLEditorWindow: View {
    let target: YAMLWindowTarget
    @State private var model: YAMLEditorModel
    @Environment(\.dismiss) private var dismiss

    init(target: YAMLWindowTarget) {
        self.target = target
        _model = State(initialValue: YAMLEditorModel(target: target))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header(model: model)
            Divider()
            if let error = model.error {
                StatusBanner(
                    message: error.errorDescription ?? "Apply failed.",
                    kind: .error
                )
                Divider()
            } else if model.applied {
                StatusBanner(
                    message: "Changes applied successfully.",
                    kind: .success
                )
                Divider()
            }
            CodeEditorView(text: $model.text)
        }
        .navigationTitle(target.windowTitle)
        .task { await model.load() }
    }

    private func header(model: YAMLEditorModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.plaintext")
                .foregroundStyle(.secondary)
            Text(model.headerLabel)
                .font(.headline)
                .lineLimit(1)
            if !model.namespace.isEmpty {
                Text(model.namespace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Spacer()

            Button {
                Task { await model.load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading || model.isApplying)

            Button {
                Task { await model.apply() }
            } label: {
                if model.isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Apply", systemImage: "checkmark.circle")
                }
            }
            .keyboardShortcut("s")
            .disabled(!model.isDirty || model.isApplying || model.isLoading)

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
        .padding(10)
    }
}
