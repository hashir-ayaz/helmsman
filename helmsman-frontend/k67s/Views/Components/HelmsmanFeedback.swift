import SwiftUI

/// Shared brand + semantic colors for product UI polish moments.
/// Amber is the instrument-panel accent from DESIGN.md; used sparingly on CTAs and active indicators.
enum HelmsmanBrand {
    /// Solar amber — primary CTA / active progress.
    static let amber = Color(red: 0.91, green: 0.52, blue: 0.22)
    /// Near-black with warm chroma (brand canvas).
    static let canvas = Color(red: 0.14, green: 0.13, blue: 0.12)
    /// Primary text on dark surfaces.
    static let ink = Color(red: 0.97, green: 0.96, blue: 0.95)
    /// Secondary text on dark surfaces (~#8E8E93 with slight warmth).
    static let muted = Color(red: 0.58, green: 0.56, blue: 0.54)

    static let danger = Color.red
    static let warning = Color.orange
    static let success = Color.green
}

/// Reusable tip / guidance chip used by bootstrap and full-pane errors.
struct TipCallout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 420)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HelmsmanBrand.amber.opacity(0.28), lineWidth: 1)
            )
    }
}

/// Compact inline failure with icon + optional Retry — for detail panes and overview panels.
struct InlineErrorBanner: View {
    let message: String
    var tip: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HelmsmanBrand.warning)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let tip, !tip.isEmpty {
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            HelmsmanBrand.warning.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(HelmsmanBrand.warning.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Top status strip for window editors (YAML apply, etc.).
struct StatusBanner: View {
    enum Kind {
        case error
        case success
        case warning

        var tint: Color {
            switch self {
            case .error, .warning: HelmsmanBrand.warning
            case .success: HelmsmanBrand.success
            }
        }

        var symbol: String {
            switch self {
            case .error, .warning: "exclamationmark.triangle.fill"
            case .success: "checkmark.circle.fill"
            }
        }
    }

    let message: String
    let kind: Kind

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .padding(.top, 2)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(kind.tint.opacity(0.14))
        .accessibilityElement(children: .combine)
    }
}
