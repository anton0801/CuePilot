import SwiftUI

// MARK: - Cards

struct CueCard<Content: View>: View {
    var accent: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .padding(.leading, accent == nil ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.card)
                if let accent {
                    Rectangle().fill(accent).frame(width: 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: 1)
        )
        .shadow(color: Palette.ink.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Typo.eyebrow)
                .tracking(1.2)
                .foregroundColor(Palette.muted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Typo.monoCaption)
                    .foregroundColor(Palette.muted)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Label/value pair inside cards.
struct InfoRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var valueColor: Color = Palette.ink
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.muted)
                    .frame(width: 20)
            }
            Text(label)
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? Typo.monoHeadline : Typo.headline)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var tint: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typo.eyebrow)
                .tracking(0.8)
                .foregroundColor(Palette.muted)
            Text(value)
                .font(Typo.timer(24))
                .foregroundColor(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badges

struct StatusBadge: View {
    enum Style {
        case blue, red, yellow, neutral, onBlue
    }

    let text: String
    let systemImage: String?
    var style: Style = .neutral

    init(_ text: String, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
            }
            Text(text).font(Typo.captionBold)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch style {
        case .blue: return Palette.blueInk
        case .red: return Palette.redInk
        case .yellow: return Palette.ink
        case .neutral: return Palette.muted
        case .onBlue: return .white
        }
    }

    private var background: Color {
        switch style {
        case .blue: return Palette.blueInk.opacity(0.09)
        case .red: return Palette.stageRed.opacity(0.1)
        case .yellow: return Palette.spotlight.opacity(0.55)
        case .neutral: return Palette.paperShade
        case .onBlue: return Color.white.opacity(0.14)
        }
    }

    private var border: Color {
        switch style {
        case .blue: return Palette.blueInk.opacity(0.2)
        case .red: return Palette.redInk.opacity(0.25)
        case .yellow: return Palette.spotlightDeep.opacity(0.6)
        case .neutral: return Palette.rule
        case .onBlue: return Color.white.opacity(0.25)
        }
    }
}

extension StatusBadge {
    static func outcome(_ outcome: RunOutcome?) -> StatusBadge {
        guard let outcome else { return StatusBadge("In Progress", systemImage: "record.circle", style: .yellow) }
        switch outcome {
        case .completed: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .blue)
        case .endedEarly: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .neutral)
        case .interrupted: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .red)
        }
    }

    static func mode(_ mode: RunMode) -> StatusBadge {
        StatusBadge(mode.title, systemImage: mode.symbol, style: .neutral)
    }

    static var partial: StatusBadge { StatusBadge("Partial Run", systemImage: "circle.lefthalf.filled", style: .neutral) }
    static var optional: StatusBadge { StatusBadge("Optional", systemImage: "circle.dashed", style: .neutral) }
    static var draft: StatusBadge { StatusBadge("Draft", systemImage: "pencil", style: .yellow) }
    static var published: StatusBadge { StatusBadge("Published", systemImage: "lock.fill", style: .blue) }
    static var current: StatusBadge { StatusBadge("Current", systemImage: "star.fill", style: .blue) }
    static var changed: StatusBadge { StatusBadge("Changed", systemImage: "arrow.triangle.2.circlepath", style: .yellow) }
}

/// Deviation text that never relies on color alone: symbol + words + signed time.
struct DeviationLabel: View {
    let seconds: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(compact ? TimeFormat.delta(seconds) : "\(word) \(TimeFormat.delta(seconds))")
                .font(Typo.monoCaption.weight(.bold))
        }
        .foregroundColor(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word) \(TimeFormat.spoken(abs(seconds)))")
    }

    private var symbol: String {
        if seconds > 0 { return "exclamationmark.triangle.fill" }
        if seconds < 0 { return "arrow.down.circle.fill" }
        return "equal.circle.fill"
    }

    private var word: String {
        if seconds > 0 { return "Exceeded" }
        if seconds < 0 { return "Under" }
        return "On plan"
    }

    private var color: Color {
        seconds > 0 ? Palette.redInk : Palette.blueInk
    }
}

// MARK: - Empty state & banners

struct EmptyStateView: View {
    let asset: String
    let size: CGSize
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Illustration(asset, size: size)
            Text(title)
                .font(Typo.title)
                .foregroundColor(Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.cue(.primary, fullWidth: false))
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

struct NoticeBanner: View {
    enum Tone { case info, warning, spotlight }

    let text: String
    var systemImage: String = "info.circle.fill"
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(iconColor)
                .padding(.top, 1)
            Text(text)
                .font(Typo.callout)
                .foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch tone {
        case .info: return Palette.blueInk
        case .warning: return Palette.redInk
        case .spotlight: return Palette.ink
        }
    }

    private var fill: Color {
        switch tone {
        case .info: return Palette.blueInk.opacity(0.06)
        case .warning: return Palette.stageRed.opacity(0.08)
        case .spotlight: return Palette.spotlight.opacity(0.35)
        }
    }

    private var stroke: Color {
        switch tone {
        case .info: return Palette.blueInk.opacity(0.15)
        case .warning: return Palette.redInk.opacity(0.25)
        case .spotlight: return Palette.spotlightDeep.opacity(0.5)
        }
    }
}

/// Transient confirmation ("Marker saved at 1:23").
struct ToastView: View {
    let text: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(Palette.spotlight)
            Text(text).font(Typo.headline).foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(Palette.midnightDeep.opacity(0.94)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal proportional bar (comparison and plan-vs-actual rows).
struct DurationBar: View {
    let value: Double
    let maxValue: Double
    var color: Color
    var marker: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.paperShade)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, width * CGFloat(min(1, value / max(maxValue, 1)))))
                if let marker {
                    Rectangle()
                        .fill(Palette.ink.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, width * CGFloat(min(1, marker / max(maxValue, 1))) - 1))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Centers content and caps its width on iPad.
    func readableWidth() -> some View {
        frame(maxWidth: Metrics.maxContentWidth).frame(maxWidth: .infinity)
    }
}
