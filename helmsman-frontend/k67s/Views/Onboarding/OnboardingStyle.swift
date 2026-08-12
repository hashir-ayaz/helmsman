import SwiftUI

/// Visual tokens matching the notch-app onboarding reference (pure black chrome).
enum OnboardingStyle {
    static let background = Color.black
    static let title = Color.white
    static let body = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) // #8E8E93
    static let accent = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255) // #007AFF
    static let progressInactive = Color.white.opacity(0.2)
    static let mediaFill = Color(white: 0.07)
    static let mediaStroke = Color.white.opacity(0.06)
    static let skip = body
    static let back = Color.white.opacity(0.4)

    static let titleFont = Font.system(size: 34, weight: .bold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .default)

    static let horizontalPadding: CGFloat = 44
    static let footerBottomPadding: CGFloat = 32
    static let mediaCornerRadius: CGFloat = 24
    static let copyMaxWidth: CGFloat = 360
    static let splitCopyWidthFraction: CGFloat = 0.36
    static let mediaVerticalPadding: CGFloat = 56
}
