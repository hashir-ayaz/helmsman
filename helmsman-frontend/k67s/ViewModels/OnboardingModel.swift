import Foundation

/// Drives the first-run onboarding carousel and persists completion in UserDefaults.
@Observable
@MainActor
final class OnboardingModel {
    static let completedKey = "hasCompletedOnboarding"

    private(set) var index: Int = 0
    /// Observed by ContentView so Skip / Get Started dismiss the tour.
    private(set) var isComplete: Bool

    var steps: [OnboardingStep] { OnboardingStep.all }

    var current: OnboardingStep {
        steps[index]
    }

    var stepCount: Int { steps.count }

    var canGoBack: Bool { index > 0 }

    var isLastStep: Bool { index >= steps.count - 1 }

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    init() {
        isComplete = Self.hasCompletedOnboarding
    }

    func goNext() {
        if isLastStep {
            finish()
            return
        }
        index = min(index + 1, steps.count - 1)
    }

    func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    func skip() {
        finish()
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        isComplete = true
    }
}
