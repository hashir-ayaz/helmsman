import SwiftUI

/// Full-window first-run onboarding. Return advances; Escape skips on welcome.
struct OnboardingView: View {
    var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingStyle.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                page
                    .id(model.current.id)
                    .transition(pageTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingFooter(
                    stepCount: model.stepCount,
                    currentIndex: model.index,
                    showsBack: model.canGoBack,
                    showsSkip: model.current.showsSkip,
                    ctaTitle: model.current.ctaTitle,
                    onBack: { withAnimation(motion) { model.goBack() } },
                    onSkip: { model.skip() },
                    onContinue: { advance() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var page: some View {
        switch model.current.layout {
        case .centered:
            OnboardingCenteredPage(step: model.current)
        case .split:
            OnboardingSplitPage(step: model.current)
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : HelmsmanMotion.soft
    }

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    private func advance() {
        withAnimation(model.isLastStep ? nil : motion) {
            model.goNext()
        }
    }
}

#Preview {
    OnboardingView(model: OnboardingModel())
        .frame(width: 1100, height: 700)
}
