import SwiftUI

enum CueButtonKind {
    /// Spotlight Yellow — the one main action on a screen.
    case primary
    /// Light card with ink border.
    case secondary
    /// Midnight Blue filled.
    case stage
    /// Destructive, red ink on light.
    case destructive
    /// Quiet text-only action.
    case plain
    /// Translucent white on blue backgrounds.
    case onBlue
}

struct CueButtonStyle: ButtonStyle {
    var kind: CueButtonKind = .primary
    var fullWidth = true
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .headline, design: .rounded).weight(.bold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundColor(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Metrics.minTap : 52)
            .background(background(pressed: configuration.isPressed))
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .shadow(color: shadowColor, radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 4)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Palette.ink
        case .secondary: return Palette.ink
        case .stage: return .white
        case .destructive: return Palette.redInk
        case .plain: return Palette.blueInk
        case .onBlue: return .white
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            LinearGradient(colors: [Color(hex: 0xFFE57E), Palette.spotlight, Palette.spotlightDeep],
                           startPoint: .top, endPoint: .bottom)
                .brightness(pressed ? -0.05 : 0)
        case .secondary:
            Palette.card.brightness(pressed ? -0.04 : 0)
        case .stage:
            LinearGradient(colors: [Palette.midnightLift, Palette.midnight], startPoint: .top, endPoint: .bottom)
                .brightness(pressed ? -0.05 : 0)
        case .destructive:
            Palette.card.brightness(pressed ? -0.04 : 0)
        case .plain:
            Color.clear
        case .onBlue:
            Color.white.opacity(pressed ? 0.2 : 0.12)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .secondary:
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1.5)
        case .destructive:
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Palette.redInk.opacity(0.35), lineWidth: 1.5)
        case .onBlue:
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        case .primary:
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        default:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return Palette.spotlightDeep.opacity(0.45)
        case .stage: return Palette.midnight.opacity(0.3)
        case .secondary, .destructive: return Palette.ink.opacity(0.06)
        case .plain, .onBlue: return .clear
        }
    }
}

extension ButtonStyle where Self == CueButtonStyle {
    static var cuePrimary: CueButtonStyle { CueButtonStyle(kind: .primary) }
    static var cueSecondary: CueButtonStyle { CueButtonStyle(kind: .secondary) }
    static var cueStage: CueButtonStyle { CueButtonStyle(kind: .stage) }
    static var cueDestructive: CueButtonStyle { CueButtonStyle(kind: .destructive) }
    static var cuePlain: CueButtonStyle { CueButtonStyle(kind: .plain, fullWidth: false, compact: true) }
    static var cueOnBlue: CueButtonStyle { CueButtonStyle(kind: .onBlue) }

    static func cue(_ kind: CueButtonKind, fullWidth: Bool = true, compact: Bool = false) -> CueButtonStyle {
        CueButtonStyle(kind: kind, fullWidth: fullWidth, compact: compact)
    }
}

/// A 44×44 round icon button used in headers.
struct HeaderIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = .white
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(filled ? Palette.ink : tint)
                .frame(width: Metrics.minTap, height: Metrics.minTap)
                .background(
                    Circle().fill(filled ? Palette.spotlight : Color.white.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Small bordered chip button used inside cards (for example "Reorder", "Duplicate").
struct ChipButton: View {
    let title: String
    let systemImage: String
    var tint: Color = Palette.blueInk
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.minTap)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
