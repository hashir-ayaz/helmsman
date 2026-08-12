import SwiftUI

/// Rounded video slot for split onboarding pages. Swap contents for AVPlayer later.
struct OnboardingMediaPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingStyle.mediaCornerRadius, style: .continuous)
                .fill(OnboardingStyle.mediaFill)
            RoundedRectangle(cornerRadius: OnboardingStyle.mediaCornerRadius, style: .continuous)
                .strokeBorder(OnboardingStyle.mediaStroke, lineWidth: 1)

            VStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(OnboardingStyle.body.opacity(0.7))
                Text("Video")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingStyle.body)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
