import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Palette from the spec. Blue dominates heroes and the stage, red takes large side elements,
/// yellow is used sparingly as a spotlight (primary action, current segment).
enum Palette {
    static let midnight = Color(hex: 0x142B69)
    static let midnightDeep = Color(hex: 0x0B1A45)
    static let midnightLift = Color(hex: 0x21408F)
    static let stageRed = Color(hex: 0xE74743)
    /// Red for text and symbols on light backgrounds (meets contrast for small text).
    static let redInk = Color(hex: 0xB42F2B)
    static let spotlight = Color(hex: 0xFFDC58)
    static let spotlightDeep = Color(hex: 0xF2C230)
    static let paper = Color(hex: 0xFFF8EB)
    static let paperShade = Color(hex: 0xF5EBD6)
    static let card = Color(hex: 0xFFFDF8)
    static let rule = Color(hex: 0xE8DDC6)
    static let ink = Color(hex: 0x18243D)
    static let muted = Color(hex: 0x63708C)
    /// Secondary text on Midnight Blue.
    static let onBlueMuted = Color(hex: 0xB8C4E6)
    /// Neutral "on plan / under plan" accent on light backgrounds.
    static let blueInk = Color(hex: 0x1F3F94)
}

enum Metrics {
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 16
    static let chipRadius: CGFloat = 10
    static let minTap: CGFloat = 44
    static let gutter: CGFloat = 16
    static let maxContentWidth: CGFloat = 720
}

enum Typo {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced digits keep timers from jittering.
    static func timer(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .default)
    static let callout = Font.system(.callout, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let captionBold = Font.system(.caption, design: .rounded).weight(.bold)
    static let mono = Font.system(.body, design: .rounded).monospacedDigit()
    static let monoHeadline = Font.system(.headline, design: .rounded).monospacedDigit()
    static let monoCaption = Font.system(.caption, design: .rounded).monospacedDigit()
    static let eyebrow = Font.system(.caption2, design: .rounded).weight(.heavy)
}

/// Global UIKit appearance needed on iOS 15 (no `scrollContentBackground` yet).
enum AppearanceSetup {
    static func apply() {
        UITextView.appearance().backgroundColor = .clear

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Palette.card)
        tab.shadowColor = UIColor(Palette.rule)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Palette.muted)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Palette.muted)]
        item.selected.iconColor = UIColor(Palette.midnight)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Palette.midnight)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
