import SwiftUI

/// Welcome / Ready centered layout with optional checkmark.
struct OnboardingCenteredPage: View {
    let step: OnboardingStep

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var checkmark: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.25)
                .frame(width: 48, height: 48)
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .ultraLight))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
