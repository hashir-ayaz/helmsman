import Foundation

/// One screen in the first-run onboarding carousel.
enum OnboardingLayout: Equatable, Sendable {
    case centered
    case split
}

struct OnboardingStep: Identifiable, Equatable, Sendable {
    let id: String
    let layout: OnboardingLayout
    let headline: String
    let subhead: String
    /// When true, show a checkmark circle under the copy (Ready screen).
    let showsCheckmark: Bool
    /// Primary button label without the ↵ glyph.
    let ctaTitle: String
    /// Skip appears only on the welcome step.
    let showsSkip: Bool

    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: "welcome",
            layout: .centered,
            headline: "Your cluster. But clearer.",
            subhead: "Let's set you up with a faster way to work Kubernetes on Mac.",
            showsCheckmark: false,
            ctaTitle: "Continue",
            showsSkip: true
        ),
        OnboardingStep(
            id: "browse",
            layout: .split,
            headline: "Every resource, one table",
            subhead: "Pods, Deployments, CRDs — kubectl-identical columns from your kubeconfig.",
            showsCheckmark: false,
            ctaTitle: "Continue",
            showsSkip: false
        ),
        OnboardingStep(
            id: "live",
            layout: .split,
            headline: "Lists that update themselves",
            subhead: "Live watch streams keep every table current — no refresh.",
            showsCheckmark: false,
            ctaTitle: "Continue",
            showsSkip: false
        ),
        OnboardingStep(
            id: "inspect",
            layout: .split,
            headline: "Logs and YAML, one click away",
            subhead: "Stream pod logs or edit YAML in a dedicated window without leaving the app.",
            showsCheckmark: false,
            ctaTitle: "Continue",
            showsSkip: false
        ),
        OnboardingStep(
            id: "act",
            layout: .split,
            headline: "Scale, restart, roll back",
            subhead: "Workload actions from the row — no juggling kubectl one-liners.",
            showsCheckmark: false,
            ctaTitle: "Continue",
            showsSkip: false
        ),
        OnboardingStep(
            id: "ready",
            layout: .centered,
            headline: "You're ready",
            subhead: "Pick a context and open your first live table.",
            showsCheckmark: true,
            ctaTitle: "Get Started",
            showsSkip: false
        ),
    ]
}
