import SwiftUI

/// Welcome / Ready centered layout with optional checkmark.
struct OnboardingCenteredPage: View {
    let step: OnboardingStep

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [OnboardingStyle.glow, .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    Text(step.headline)
                        .font(OnboardingStyle.titleFont)
                        .foregroundStyle(OnboardingStyle.title)
                        .multilineTextAlignment(.center)

                    Text(step.subhead)
                        .font(OnboardingStyle.bodyFont)
                        .foregroundStyle(OnboardingStyle.body)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 440)

                    if step.showsCheckmark {
                        checkmark
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, OnboardingStyle.horizontalPadding)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var checkmark: some View {
        ZStack {
            Circle()
                .strokeBorder(OnboardingStyle.accent.opacity(0.9), lineWidth: 1.5)
                .frame(width: 48, height: 48)
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .ultraLight))
                .foregroundStyle(OnboardingStyle.accent)
        }
        .accessibilityHidden(true)
    }
}
