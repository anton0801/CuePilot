import SwiftUI

struct OnboardingPage: Identifiable {
    let id: Int
    let asset: String
    let title: String
    let message: String
    let reassurance: String
    let fallbackSymbol: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0, asset: ArtAsset.onboardingSegments,
            title: "Give Every Part Its Moment",
            message: "Build your performance one clear segment at a time.",
            reassurance: "Name a part, give it a planned time and a short cue.",
            fallbackSymbol: "rectangle.stack"
        ),
        OnboardingPage(
            id: 1, asset: ArtAsset.onboardingStage,
            title: "Stay with the Performance",
            message: "Follow your cues and keep an eye on time.",
            reassurance: "No microphone, no recording — just a real timer and your next cue.",
            fallbackSymbol: "timer"
        ),
        OnboardingPage(
            id: 2, asset: ArtAsset.onboardingReview,
            title: "Find the Parts to Refine",
            message: "Compare runs and keep your own rehearsal notes.",
            reassurance: "You see actual time per segment and your own markers. No automatic scores.",
            fallbackSymbol: "rectangle.split.2x1"
        )
    ]
}

/// Three onboarding pages. Finishing or skipping opens Home; nothing is pre-created.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = OnboardingPage.all

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    OnboardingBackground(page: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip", action: onFinish)
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Metrics.minTap)
                            .background(Capsule().fill(Color.black.opacity(0.25)))
                            .accessibilityHint("Opens Home")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
                panel
            }
            .readableWidth()
        }
        .background(Palette.midnight.ignoresSafeArea())
    }

    private var panel: some View {
        let item = pages[page]
        return VStack(alignment: .leading, spacing: 14) {
            progress
            Text(item.title)
                .font(Typo.display(32))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(item.message)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(Palette.spotlight)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.reassurance)
                .font(Typo.callout)
                .foregroundColor(Palette.onBlueMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back") { go(to: page - 1) }
                        .buttonStyle(.cue(.onBlue))
                        .frame(maxWidth: 140)
                }
                if page < pages.count - 1 {
                    Button("Next") { go(to: page + 1) }
                        .buttonStyle(.cuePrimary)
                } else {
                    Button("Get Started", action: onFinish)
                        .buttonStyle(.cuePrimary)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(pages) { item in
                Capsule()
                    .fill(item.id == page ? Palette.spotlight : Color.white.opacity(0.3))
                    .frame(width: item.id == page ? 28 : 10, height: 6)
            }
            Text("\(page + 1)/\(pages.count)")
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(pages.count)")
    }

    private func go(to index: Int) {
        if reduceMotion {
            page = index
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { page = index }
        }
    }
}

private struct OnboardingBackground: View {
    let page: OnboardingPage

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = BundleImage.webp(page.asset) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .clipped()
                } else {
                    LinearGradient(colors: [Palette.midnightLift, Palette.midnight, Palette.midnightDeep], startPoint: .top, endPoint: .bottom)
                    Image(systemName: page.fallbackSymbol)
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(Palette.spotlight.opacity(0.8))
                        .offset(y: -proxy.size.height * 0.18)
                }
                // Keeps the lower third calm and the text readable.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: Palette.midnightDeep.opacity(0.75), location: 0.66),
                        .init(color: Palette.midnightDeep.opacity(0.96), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
