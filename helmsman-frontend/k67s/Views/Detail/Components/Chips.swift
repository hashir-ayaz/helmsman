import SwiftUI

/// A single pill-shaped chip.
struct Chip: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
            .textSelection(.enabled)
    }
}

/// Renders a string map as wrapping `key=value` chips.
struct KeyValueChips: View {
    let pairs: [String: JSONValue]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(pairs.keys.sorted(), id: \.self) { key in
                Chip(text: "\(key)=\(pairs[key]?.displayString ?? "")", tint: .blue)
            }
        }
        // Force vertical sizing from Layout's measured height so siblings
        // (e.g. Annotations) don't overlap when chips wrap.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Wrapping horizontal layout. Shared arrange logic keeps `sizeThatFits` and
/// `placeSubviews` consistent — the previous version under-reported height when
/// the width proposal was unbounded, then wrapped into that short space and
/// overlapped the next DetailSection (Labels vs Annotations).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for index in subviews.indices {
            let frame = result.frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Arrangement {
        var size: CGSize
        var frames: [CGRect]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        // Unbounded / missing width: size as a vertical stack so we never
        // report a single-row height that later placement will overflow.
        guard let proposedWidth = proposal.width, proposedWidth.isFinite, proposedWidth > 0 else {
            var y: CGFloat = 0
            var maxWidth: CGFloat = 0
            var frames: [CGRect] = []
            for (index, size) in sizes.enumerated() {
                if index > 0 { y += spacing }
                frames.append(CGRect(origin: CGPoint(x: 0, y: y), size: size))
                maxWidth = max(maxWidth, size.width)
                y += size.height
            }
            return Arrangement(size: CGSize(width: maxWidth, height: y), frames: frames)
        }

        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowMaxX: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > proposedWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            rowMaxX = max(rowMaxX, x - spacing)
        }

        let height = y + rowHeight
        return Arrangement(
            size: CGSize(width: min(proposedWidth, max(rowMaxX, 0)), height: height),
            frames: frames
        )
    }
}
