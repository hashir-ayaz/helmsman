import SwiftUI

/// Visual tokens for first-run onboarding — dark instrument panel with amber accent.
enum OnboardingStyle {
    static let background = HelmsmanBrand.canvas
    static let title = HelmsmanBrand.ink
    static let body = HelmsmanBrand.muted
    static let accent = HelmsmanBrand.amber
    static let progressInactive = Color.white.opacity(0.18)
    static let mediaFill = Color(red: 36 / 255, green: 34 / 255, blue: 31 / 255)
    static let mediaStroke = Color.white.opacity(0.08)
    static let skip = body
    static let back = Color.white.opacity(0.42)
    static let glow = HelmsmanBrand.amber.opacity(0.12)

    static let titleFont = Font.system(size: 34, weight: .bold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .default)

    static let horizontalPadding: CGFloat = 44
    static let footerBottomPadding: CGFloat = 32
    static let mediaCornerRadius: CGFloat = 20
    static let copyMaxWidth: CGFloat = 360
    static let splitCopyWidthFraction: CGFloat = 0.36
    static let mediaVerticalPadding: CGFloat = 24
    /// All onboarding captures are 1720×1080.
    static let mediaAspectRatio: CGFloat = 1720 / 1080
}
