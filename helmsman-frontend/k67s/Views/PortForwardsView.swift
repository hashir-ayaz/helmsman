import SwiftUI

struct PortForwardsView: View {
    @Bindable var app: AppModel
    @Bindable var model: PortForwardsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Port Forwards")
        .task {
            model.startPolling(ctx: app.selectedContext)
        }
        .onDisappear {
            model.stopPolling()
        }
        .onChange(of: app.selectedContext) { _, newCtx in
            Task { await model.refresh(ctx: newCtx) }
        }
    }

    private var header: some View {
        HStack {
            Text("Port Forwards")
                .font(.title2.weight(.semibold))
            Spacer()
            if model.isLoading && model.sessions.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error, model.sessions.isEmpty {
            ErrorStateView(error: error) {
                Task { await model.refresh(ctx: app.selectedContext) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.sessions.isEmpty {
            ContentUnavailableView(
                "No Port Forwards",
                systemImage: "arrow.left.arrow.right",
                description: Text("Right-click a Pod or Service and choose Port Forward to start one.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.sessions) {
                TableColumn("") { session in
                    Circle()
                        .fill(session.isActive ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                }
                .width(24)

                TableColumn("Context") { session in
                    Text(session.context)
                        .lineLimit(1)
                        .help(session.context)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Kind") { session in
                    Text(session.kind)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(kindColor(session.kind).opacity(0.2))
                        .foregroundStyle(kindColor(session.kind))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .width(72)

                TableColumn("Resource") { session in
                    Text(session.resource)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Namespace") { session in
                    Text(session.namespace)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Ports") { session in
                    Text(session.portsDescription)
                        .font(.body.monospaced())
                }
                .width(min: 160, ideal: 200)

                TableColumn("Conns") { session in
                    Text("\(session.connections)")
                        .monospacedDigit()
                }
                .width(48)

                TableColumn("↑ Sent") { session in
                    Text(PortForwardByteFormatter.format(session.bytesSent))
                        .monospacedDigit()
                }
                .width(72)

                TableColumn("↓ Received") { session in
                    Text(PortForwardByteFormatter.format(session.bytesReceived))
                        .monospacedDigit()
                }
                .width(88)
            }
            .contextMenu(forSelectionType: PortForwardSession.ID.self) { ids in
                rowMenu(for: ids)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<PortForwardSession.ID>) -> some View {
        if let id = ids.first,
           let session = model.sessions.first(where: { $0.id == id }) {
            Button {
                model.openInBrowser(session)
            } label: {
                Label("Open in Browser", systemImage: "globe")
            }

            Button {
                model.copyURL(session)
            } label: {
                Label("Copy URL", systemImage: "link")
            }

            Divider()

            if session.isActive {
                Button(role: .destructive) {
                    Task { await model.stop(ctx: app.selectedContext, session: session) }
                } label: {
                    Text("Stop")
                }
            } else {
                Button(role: .destructive) {
                    Task { await model.remove(ctx: app.selectedContext, session: session) }
                } label: {
                    Text("Remove")
                }
            }
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "Pod": .pink
        case "Service": .purple
        default: .secondary
        }
    }
}
