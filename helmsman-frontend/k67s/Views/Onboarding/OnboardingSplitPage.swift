import SwiftUI

/// Split benefit page: left copy (vertically centered), right looping video.
struct OnboardingSplitPage: View {
    let step: OnboardingStep

    var body: some View {
        GeometryReader { geo in
            let copyWidth = max(geo.size.width * OnboardingStyle.splitCopyWidthFraction, 280)

            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(step.headline)
                        .font(OnboardingStyle.titleFont)
                        .foregroundStyle(OnboardingStyle.title)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.subhead)
                        .font(OnboardingStyle.bodyFont)
                        .foregroundStyle(OnboardingStyle.body)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: OnboardingStyle.copyMaxWidth, alignment: .leading)
                }
                .frame(width: copyWidth, alignment: .leading)
                .padding(.leading, OnboardingStyle.horizontalPadding)

                OnboardingMediaPlaceholder(videoName: step.videoName, mediaLabel: step.headline)
                    .aspectRatio(OnboardingStyle.mediaAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, OnboardingStyle.horizontalPadding)
                    .padding(.vertical, OnboardingStyle.mediaVerticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
