import SwiftUI

/// A rounded red stage curtain drawn with gradients (UI decoration, not a raster asset).
struct CurtainPanel: View {
    var folds = 4
    var edge: HorizontalEdge = .leading

    private static let foldColors: [Color] = [
        Color(hex: 0xA62A27), Palette.stageRed, Color(hex: 0xF0706B), Palette.stageRed, Color(hex: 0xA62A27)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(folds)
            HStack(spacing: 0) {
                ForEach(0..<folds, id: \.self) { _ in
                    LinearGradient(colors: Self.foldColors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                }
            }
            .clipShape(CurtainShape(edge: edge))
            .overlay(
                CurtainShape(edge: edge)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
        }
        .accessibilityHidden(true)
    }
}

/// Curtain silhouette: straight at the outer edge, swept in toward the bottom at the inner edge.
struct CurtainShape: Shape {
    var edge: HorizontalEdge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.45
        if edge == .leading {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY),
                              control: CGPoint(x: rect.maxX - inset * 0.1, y: rect.maxY * 0.75))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 10),
                              control: CGPoint(x: rect.minX + inset * 0.3, y: rect.maxY + 6))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY),
                              control: CGPoint(x: rect.minX + inset * 0.1, y: rect.maxY * 0.75))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 10),
                              control: CGPoint(x: rect.maxX - inset * 0.3, y: rect.maxY + 6))
        }
        path.closeSubpath()
        return path
    }
}

/// Midnight hero with side curtains and a soft spotlight pool.
struct StageHeroBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Palette.midnightDeep, Palette.midnight, Palette.midnightLift], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.spotlight.opacity(0.28), .clear], center: UnitPoint(x: 0.72, y: 0.35), startRadius: 10, endRadius: 220)
            HStack {
                CurtainPanel(folds: 3, edge: .leading).frame(width: 70)
                Spacer()
                CurtainPanel(folds: 3, edge: .trailing).frame(width: 46)
            }
            // Valance across the top.
            LinearGradient(colors: [Color(hex: 0xA62A27), Palette.stageRed], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
                .clipShape(RoundedCornerShape(radius: 10, corners: [.bottomLeft, .bottomRight]))
        }
        .accessibilityHidden(true)
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
