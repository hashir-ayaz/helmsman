import SwiftUI

/// Bottom chrome: back chevron, progress dashes, optional Skip, Continue / Get Started pill.
struct OnboardingFooter: View {
    let stepCount: Int
    let currentIndex: Int
    let showsBack: Bool
    let showsSkip: Bool
    let ctaTitle: String
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leftCluster
            Spacer(minLength: 16)
            continueButton
        }
        .padding(.horizontal, OnboardingStyle.horizontalPadding)
        .padding(.bottom, OnboardingStyle.footerBottomPadding)
    }

    private var leftCluster: some View {
        HStack(spacing: 14) {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.back)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            progressDashes

            if showsSkip {
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(OnboardingStyle.skip)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var progressDashes: some View {
        HStack(spacing: 4) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? OnboardingStyle.accent : OnboardingStyle.progressInactive)
                    .frame(width: i == currentIndex ? 20 : 9, height: 2.5)
                    .animation(HelmsmanMotion.soft, value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(stepCount)")
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: 7) {
                Text(ctaTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text("↵")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(OnboardingStyle.title)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(OnboardingStyle.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("\(ctaTitle), Return")
    }
}
