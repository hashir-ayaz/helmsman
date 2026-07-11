import SwiftUI

// MARK: - Motion

enum HelmsmanMotion {
    static let snappy = Animation.easeOut(duration: 0.18)
    static let soft = Animation.easeInOut(duration: 0.22)
    static let gate = Animation.easeOut(duration: 0.2)
}

// MARK: - Primitives

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .redacted(reason: .placeholder)
            .skeletonPulse()
    }
}

struct SkeletonCircle: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: size, height: size)
            .redacted(reason: .placeholder)
            .skeletonPulse()
    }
}

private struct SkeletonPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (isDimmed ? 0.55 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

extension View {
    func skeletonPulse() -> some View {
        modifier(SkeletonPulseModifier())
    }

    func contentAppear() -> some View {
        modifier(ContentAppearModifier())
    }
}

private struct ContentAppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(HelmsmanMotion.snappy) {
                        visible = true
                    }
                }
            }
    }
}

// MARK: - Resource list skeleton

struct ResourceListSkeleton: View {
    var rowCount: Int = 8
    var columnCount: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(0..<rowCount, id: \.self) { _ in
                dataRow
                Divider()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { index in
                SkeletonBar(width: index == 0 ? 100 : 72, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var dataRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                SkeletonCircle(size: 8)
                SkeletonBar(width: 120, height: 12)
            }
            ForEach(1..<columnCount, id: \.self) { index in
                SkeletonBar(width: index == 1 ? 80 : 64, height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Cluster overview skeleton

struct ClusterOverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    summaryCardSkeleton
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SkeletonBar(width: 120, height: 14)
                ForEach(0..<4, id: \.self) { _ in
                    workloadBarSkeleton
                }
            }

            HSplitView {
                panelSkeleton(rowCount: 4)
                    .frame(minWidth: 280)
                panelSkeleton(rowCount: 5)
                    .frame(minWidth: 320)
            }
            .frame(minHeight: 280)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonCircle(size: 20)
            SkeletonBar(width: 48, height: 28, cornerRadius: 6)
            SkeletonBar(width: 72, height: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var workloadBarSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBar(width: 88, height: 12)
            SkeletonBar(height: 6, cornerRadius: 3)
            SkeletonBar(width: 160, height: 10)
        }
    }

    private func panelSkeleton(rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBar(width: 120, height: 14)
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: 8) {
                    SkeletonCircle(size: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonBar(width: 100, height: 12)
                        SkeletonBar(width: 180, height: 10)
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Detail pane skeletons

struct DetailOverviewSkeleton: View {
    var rowCount: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection(title: "Overview") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        HStack {
                            SkeletonBar(width: 72, height: 12)
                            Spacer()
                            SkeletonBar(width: index.isMultiple(of: 2) ? 96 : 64, height: 12)
                        }
                    }
                }
            }
            DetailSection(title: "Conditions") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBar(height: 32, cornerRadius: 6)
                    }
                }
            }
        }
    }
}

struct DetailObjectSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<8, id: \.self) { level in
                HStack(spacing: 8) {
                    SkeletonBar(width: 8, height: 8, cornerRadius: 2)
                    SkeletonBar(width: CGFloat(80 + level * 12), height: 12)
                }
                .padding(.leading, CGFloat(level * 16))
            }
        }
    }
}

struct DetailYAMLSkeleton: View {
    var lineCount: Int = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<lineCount, id: \.self) { index in
                SkeletonBar(
                    width: CGFloat([220, 180, 160, 200, 140, 190, 170, 150][index % 8]),
                    height: 11,
                    cornerRadius: 2
                )
            }
        }
        .font(.system(.caption, design: .monospaced))
    }
}

struct PodEventsSkeleton: View {
    var rowCount: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(alignment: .top, spacing: 8) {
                    SkeletonCircle(size: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonBar(width: 88, height: 12)
                        SkeletonBar(width: 160, height: 10)
                    }
                }
            }
        }
    }
}
