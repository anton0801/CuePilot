import SwiftUI

/// Renders a tab root plus the pushed screens of a `Router`, with slide transitions and an edge-swipe back gesture.
///
/// Lower screens stay alive underneath (like UINavigationController), so their state survives a push.
struct RouterStackView<Root: View>: View {
    @ObservedObject var router: Router
    let root: Root
    let destination: (Route) -> AnyView

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(router: Router, @ViewBuilder root: () -> Root, destination: @escaping (Route) -> AnyView) {
        self.router = router
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                root
                    .environmentObject(router)
                    .allowsHitTesting(router.stack.isEmpty)
                    .accessibilityHidden(!router.stack.isEmpty)

                ForEach(Array(router.stack.enumerated()), id: \.element.id) { index, entry in
                    let isTop = index == router.stack.count - 1
                    destination(entry.route)
                        .environment(\.routeEntryID, entry.id)
                        .environmentObject(router)
                        .background(Palette.paper.ignoresSafeArea())
                        .shadow(color: Color.black.opacity(isTop && dragOffset > 0 ? 0.18 : 0), radius: 12, x: -4, y: 0)
                        .offset(x: isTop ? dragOffset : 0)
                        .allowsHitTesting(isTop && !isDragging)
                        .accessibilityHidden(!isTop)
                        .overlay(alignment: .leading) {
                            if isTop && !router.popBlocked.contains(entry.id) {
                                edgeSwipeZone(width: proxy.size.width)
                            }
                        }
                        .zIndex(Double(index + 1))
                        .transition(transition)
                }
            }
        }
    }

    private var transition: AnyTransition {
        (router.reduceMotion || systemReduceMotion) ? .opacity : .move(edge: .trailing)
    }

    /// A narrow strip on the leading edge; content keeps a 16 pt gutter so nothing interactive sits under it.
    private func edgeSwipeZone(width: CGFloat) -> some View {
        Color.clear
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = max(0, value.translation.width)
                    }
                    .onEnded { value in
                        let shouldPop = value.translation.width > width * 0.33 || value.predictedEndTranslation.width > width * 0.6
                        if shouldPop {
                            withAnimation(.easeOut(duration: 0.18)) { dragOffset = width }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 190_000_000)
                                router.popImmediately()
                                dragOffset = 0
                                isDragging = false
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                            isDragging = false
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}
