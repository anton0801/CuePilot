import SwiftUI

/// "Opening night": the curtains part, a spotlight comes on, Flick steps into the light and a stage timer fills.
struct SplashView: View {
    let reduceMotion: Bool
    let onFinish: () -> Void

    @State private var curtainsOpen = false
    @State private var spotlightOn = false
    @State private var flickIn = false
    @State private var glowPulse = false
    @State private var titleIn = false
    @State private var sparkle = false
    @State private var progress: CGFloat = 0
    @State private var didFinish = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let floorY = size.height * 0.6
            ZStack {
                backdrop(size: size, floorY: floorY)
                
                Image("main-back-imag")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .opacity(0.8)
                    .ignoresSafeArea()

                SpotlightBeam()
                    .fill(LinearGradient(colors: [Palette.spotlight.opacity(0.55), Palette.spotlight.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size.width * 0.86, height: floorY - 40)
                    .position(x: size.width / 2, y: 40 + (floorY - 40) / 2)
                    .opacity(spotlightOn ? 1 : 0)
                    .blur(radius: 1.5)

                Ellipse()
                    .fill(RadialGradient(colors: [Palette.spotlight.opacity(0.5), Palette.spotlight.opacity(0)],
                                         center: .center, startRadius: 4, endRadius: size.width * 0.42))
                    .frame(width: size.width * 0.86, height: 96)
                    .position(x: size.width / 2, y: floorY)
                    .scaleEffect(spotlightOn ? 1 : 0.5)
                    .opacity(spotlightOn ? 1 : 0)

                sparkles(size: size, floorY: floorY)

                Circle()
                    .fill(RadialGradient(colors: [Palette.spotlight.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .position(x: size.width / 2, y: floorY - 88)
                    .scaleEffect(glowPulse ? 1.08 : 0.92)
                    .opacity(flickIn ? 1 : 0)

                Illustration(ArtAsset.flickDirector, size: CGSize(width: 150, height: 171))
                    .scaleEffect(flickIn ? 1 : 0.35, anchor: .bottom)
                    .opacity(flickIn ? 1 : 0)
                    .position(x: size.width / 2, y: floorY - 80)

                title
                    .frame(width: min(size.width - 48, 420))
                    .position(x: size.width / 2, y: floorY + (size.height - floorY) * 0.42)
                    .opacity(titleIn ? 1 : 0)
                    .offset(y: titleIn ? 0 : 18)

                curtains(size: size)

                Valance()
                    .fill(LinearGradient(colors: [Color(hex: 0x8F211F), Palette.stageRed], startPoint: .top, endPoint: .bottom))
                    .overlay(Valance().stroke(Color(hex: 0xE9B949), lineWidth: 3))
                    .frame(height: proxy.safeAreaInsets.top + 58)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .onAppear(perform: play)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cue Pilot")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Pieces

    private func backdrop(size: CGSize, floorY: CGFloat) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Palette.midnightDeep, Palette.midnight, Palette.midnightDeep], startPoint: .top, endPoint: .bottom)
            // Back-wall pleats, very soft.
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    LinearGradient(colors: [Color.white.opacity(0.0), Color.white.opacity(index.isMultiple(of: 2) ? 0.035 : 0.015), Color.white.opacity(0.0)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(height: floorY)
            // Stage floor.
            LinearGradient(colors: [Palette.midnightLift, Palette.midnightDeep], startPoint: .top, endPoint: .bottom)
                .frame(height: size.height - floorY)
                .offset(y: floorY)
            Rectangle()
                .fill(Palette.spotlight.opacity(0.35))
                .frame(height: 2)
                .offset(y: floorY)
        }
    }

    private var title: some View {
        VStack(spacing: 10) {
            Text("Cue Pilot")
                .font(Typo.display(44, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: Palette.spotlight.opacity(0.35), radius: 12)
            Text("Loading app content...")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Palette.spotlight)
            // A stage timer filling up — the app's main object, in miniature.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.spotlight, Palette.spotlightDeep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 180 * progress)
            }
            .frame(width: 180, height: 6)
            .padding(.top, 6)
            ProgressView()
                .tint(.white.opacity(0.7))
                .scaleEffect(0.7)
        }
    }

    private func sparkles(size: CGSize, floorY: CGFloat) -> some View {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.36, 0.30, 9, 0.0), (0.62, 0.24, 7, 0.25), (0.55, 0.42, 6, 0.5),
            (0.30, 0.47, 7, 0.15), (0.70, 0.40, 8, 0.4)
        ]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                Image(systemName: "sparkle")
                    .font(.system(size: spot.2, weight: .bold))
                    .foregroundColor(Palette.spotlight)
                    .position(x: size.width * spot.0, y: floorY * spot.1 + 40)
                    .opacity(sparkle ? 0.9 : 0)
                    .scaleEffect(sparkle ? 1 : 0.3)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(spot.3), value: sparkle)
            }
        }
    }

    private func curtains(size: CGSize) -> some View {
        // Each half gathers toward its side instead of sliding off, like real stage drapes.
        let half = size.width / 2 + 24
        let gathered: CGFloat = 40 / half
        return ZStack {
            ClosedCurtain(edge: .leading)
                .frame(width: half, height: size.height)
                .scaleEffect(x: curtainsOpen ? gathered : 1, y: 1, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ClosedCurtain(edge: .trailing)
                .frame(width: half, height: size.height)
                .scaleEffect(x: curtainsOpen ? gathered : 1, y: 1, anchor: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: Timeline

    private func play() {
        if reduceMotion {
            curtainsOpen = true
            spotlightOn = true
            flickIn = true
            titleIn = true
            sparkle = true
            progress = 1
            schedule(after: 1.0, finish)
            return
        }
        schedule(after: 0.2) {
            Haptics.light()
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 1.05)) { curtainsOpen = true }
        }
        schedule(after: 0.55) { withAnimation(.easeOut(duration: 0.6)) { spotlightOn = true } }
        schedule(after: 0.8) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { flickIn = true }
            sparkle = true
            withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) { glowPulse = true }
        }
        schedule(after: 1.1) { withAnimation(.easeOut(duration: 0.45)) { titleIn = true } }
        schedule(after: 1.2) { withAnimation(.easeInOut(duration: 15.0)) { progress = 0.95 } }
        // schedule(after: 2.45, finish)
    }

    private func schedule(after seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}

/// A closed half of the main curtain: vertical folds with a gold hem.
private struct ClosedCurtain: View {
    let edge: HorizontalEdge
    private static let fold: [Color] = [Color(hex: 0x8F211F), Palette.stageRed, Color(hex: 0xF27873), Palette.stageRed, Color(hex: 0x8F211F)]

    var body: some View {
        GeometryReader { proxy in
            let folds = 7
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(0..<folds, id: \.self) { _ in
                        LinearGradient(colors: Self.fold, startPoint: .leading, endPoint: .trailing)
                    }
                }
                // Gold hem.
                Rectangle()
                    .fill(LinearGradient(colors: [Color(hex: 0xF4CF6A), Color(hex: 0xC9962F)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 10)
                // Shadow where the two halves meet.
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: edge == .leading ? .trailing : .leading,
                               endPoint: edge == .leading ? .leading : .trailing)
                    .frame(width: 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .trailing : .leading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Scalloped valance across the top of the proscenium.
private struct Valance: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scallops = max(5, Int(rect.width / 70))
        let width = rect.width / CGFloat(scallops)
        let base = rect.maxY - 16
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        for index in (0..<scallops).reversed() {
            let start = rect.minX + CGFloat(index + 1) * width
            let end = start - width
            path.addQuadCurve(to: CGPoint(x: end, y: base), control: CGPoint(x: (start + end) / 2, y: rect.maxY + 14))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Light cone from a lamp at the top centre.
private struct SpotlightBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topHalf: CGFloat = 18
        path.move(to: CGPoint(x: rect.midX - topHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + topHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + 24))
        path.closeSubpath()
        return path
    }
}
