import SwiftUI

/// Renders a service's "Port(s)" cell (e.g. "80/TCP", "80:30007/TCP,443/TCP")
/// as colored chips, one per port, each tinted deterministically by port number.
struct PortChipsView: View {
    let value: String

    private var ports: [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                chip(for: port)
            }
        }
    }

    private func chip(for port: String) -> some View {
        let label = Self.portNumber(from: port)
        let color = Self.color(for: label)
        return Text(label)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
    }

    /// Leading numeric port from a token like "80:30007/TCP" → "80".
    private static func portNumber(from token: String) -> String {
        let digits = token.prefix { $0.isNumber }
        return digits.isEmpty ? token : String(digits)
    }

    private static let palette: [Color] = [
        .blue, .purple, .green, .orange, .teal, .pink, .indigo, .brown,
    ]

    private static func color(for label: String) -> Color {
        guard let port = Int(label) else { return .secondary }
        return palette[port % palette.count]
    }
}
