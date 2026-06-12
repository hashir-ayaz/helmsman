import SwiftUI

/// Sheet that shows rollout history for a Deployment/StatefulSet/DaemonSet and
/// lets the operator roll back to any previous revision.
struct RolloutHistorySheet: View {
    let ctx: String
    let ns: String
    let workload: String
    let name: String
    var onUndone: () -> Void = {}

    @State private var model = RolloutHistorySheetModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            if model.isLoading {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error, model.revisions.isEmpty {
                ErrorStateView(error: error) {
                    Task { await model.load(ctx: ctx, ns: ns, workload: workload, name: name) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.revisions.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                revisionList
            }
        }
        .frame(minWidth: 500, minHeight: 340)
        .task { await model.load(ctx: ctx, ns: ns, workload: workload, name: name) }
    }

    private var sheetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rollout History")
                    .font(.headline)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isUndoing {
                ProgressView()
                    .controlSize(.small)
            }
            if let error = model.error {
                Label(error.errorDescription ?? "Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(1)
            }
            Button("Done") { dismiss() }
        }
        .padding(12)
    }

    private var revisionList: some View {
        List(model.revisions) { entry in
            RevisionRow(entry: entry) {
                Task {
                    let ok = await model.undo(
                        ctx: ctx, ns: ns, workload: workload, name: name, toRevision: entry.revision
                    )
                    if ok {
                        onUndone()
                        dismiss()
                    }
                }
            }
            .disabled(model.isUndoing)
        }
        .listStyle(.plain)
    }
}

private struct RevisionRow: View {
    let entry: RevisionEntry
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Revision \(entry.revision)")
                        .font(.headline)
                    if let cause = entry.changeCause, !cause.isEmpty {
                        Text(cause)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !entry.images.isEmpty {
                    Text(entry.images.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !entry.createdAt.isEmpty {
                    Text(entry.createdAt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Undo to this", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
