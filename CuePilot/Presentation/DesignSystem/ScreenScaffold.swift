import SwiftUI

/// Midnight Blue header strip used by every pushed screen: back, title, trailing actions.
/// Sits under the (light) status bar and ends in a thin stage-red "curtain" edge.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var backAction: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @EnvironmentObject private var keyboard: KeyboardObserver

    var body: some View {
        HStack(spacing: 10) {
            if let backAction {
                HeaderIconButton(systemName: "chevron.left", label: "Back", tint: Palette.spotlight, action: backAction)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typo.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typo.caption)
                        .foregroundColor(Palette.onBlueMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if keyboard.isVisible {
                HeaderIconButton(systemName: "keyboard.chevron.compact.down", label: "Hide keyboard") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            trailing
        }
        .padding(.leading, backAction == nil ? 20 : 16)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(HeaderBackground().ignoresSafeArea(edges: .top))
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backAction: (() -> Void)?) {
        self.init(title: title, subtitle: subtitle, backAction: backAction) { EmptyView() }
    }
}

struct HeaderBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Palette.midnightDeep, Palette.midnight], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.spotlight.opacity(0.22), .clear], center: .topTrailing, startRadius: 4, endRadius: 240)
            Rectangle().fill(Palette.stageRed).frame(height: 3)
        }
    }
}

/// Standard pushed screen: header + scrolling Paper content, width-capped on iPad.
struct ScreenScaffold<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var backAction: (() -> Void)?
    var trailing: Trailing
    var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        backAction: (() -> Void)?,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: title, subtitle: subtitle, backAction: backAction) { trailing }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .readableWidth()
            }
        }
        .background(Palette.paper.ignoresSafeArea())
    }
}

extension ScreenScaffold where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backAction: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, backAction: backAction, trailing: { EmptyView() }, content: content)
    }
}

/// Standard sheet chrome: title bar with Close, Paper background.
struct SheetScaffold<Content: View>: View {
    let title: String
    var closeTitle = "Close"
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Typo.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(closeTitle, action: onClose)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Palette.spotlight)
                    .frame(minWidth: Metrics.minTap, minHeight: Metrics.minTap)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(HeaderBackground())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
                .readableWidth()
            }
        }
        .background(Palette.paper.ignoresSafeArea())
    }
}
