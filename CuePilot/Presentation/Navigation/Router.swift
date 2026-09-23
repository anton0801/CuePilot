import SwiftUI

struct RehearsalPreset: Hashable {
    var performanceID: UUID?
    var versionID: UUID?
    var mode: RunMode?
}

struct RunsFilter: Hashable {
    var performanceID: UUID?
    var versionID: UUID?
    var mode: RunMode?

    static let all = RunsFilter()
}

struct ComparePreset: Hashable {
    var performanceID: UUID?
    var runA: UUID?
    var runB: UUID?
}

struct ExportPreset: Hashable {
    var kind: ExportKind = .cueSheet
    var performanceID: UUID?
    var versionID: UUID?
    var runID: UUID?
    var runA: UUID?
    var runB: UUID?
}

/// Every pushable screen. Onboarding, Home, Stage Mode and sheets are presented outside the stack.
enum Route: Hashable {
    case library(showArchived: Bool)
    /// `nil` creates a new performance.
    case performanceEditor(UUID?)
    /// `segmentID == nil` adds a new segment.
    case segmentEditor(performanceID: UUID, segmentID: UUID?)
    case rehearsalSetup(RehearsalPreset)
    case markers(runID: UUID)
    case runs(RunsFilter)
    case review(runID: UUID)
    case compare(ComparePreset)
    case versions(performanceID: UUID, highlight: UUID?)
    case export(ExportPreset)
    case settings
}

/// A navigation stack for one tab. Implemented without NavigationStack (iOS 16+) so it behaves the same on iOS 15.
@MainActor
final class Router: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let route: Route
    }

    @Published private(set) var stack: [Entry] = []
    @Published private(set) var popBlocked: Set<UUID> = []
    var reduceMotion = false

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.28) }

    func push(_ route: Route) {
        withAnimation(animation) {
            stack.append(Entry(route: route))
        }
    }

    func pop() {
        guard !stack.isEmpty else { return }
        withAnimation(animation) {
            let removed = stack.removeLast()
            popBlocked.remove(removed.id)
        }
    }

    /// Removes the top screen without animation (used after an interactive swipe already moved it off screen).
    func popImmediately() {
        guard !stack.isEmpty else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let removed = stack.removeLast()
            popBlocked.remove(removed.id)
        }
    }

    func popToRoot() {
        guard !stack.isEmpty else { return }
        withAnimation(animation) {
            stack.removeAll()
            popBlocked.removeAll()
        }
    }

    /// Replaces the top screen, e.g. "Save" on a new performance turns the screen into the editor of the saved one.
    func replaceTop(with route: Route) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let removed = stack.popLast() { popBlocked.remove(removed.id) }
            stack.append(Entry(route: route))
        }
    }

    /// Pops back to the given screen if it exists, otherwise pushes the route.
    func show(_ route: Route) {
        if let index = stack.lastIndex(where: { $0.route == route }) {
            withAnimation(animation) {
                let removed = stack[(index + 1)...]
                removed.forEach { popBlocked.remove($0.id) }
                stack.removeSubrange((index + 1)...)
            }
        } else {
            push(route)
        }
    }

    func setPopBlocked(_ blocked: Bool, entryID: UUID?) {
        guard let entryID else { return }
        if blocked { popBlocked.insert(entryID) } else { popBlocked.remove(entryID) }
    }

    func reset(to routes: [Route]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stack = routes.map { Entry(route: $0) }
            popBlocked.removeAll()
        }
    }
}

private struct RouteEntryIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The stack entry a screen is displayed in (`nil` for tab roots).
    var routeEntryID: UUID? {
        get { self[RouteEntryIDKey.self] }
        set { self[RouteEntryIDKey.self] = newValue }
    }
}

private struct PopGestureBlocker: ViewModifier {
    let blocked: Bool
    @EnvironmentObject private var router: Router
    @Environment(\.routeEntryID) private var entryID

    func body(content: Content) -> some View {
        content
            .onAppear { router.setPopBlocked(blocked, entryID: entryID) }
            .onChange(of: blocked) { router.setPopBlocked($0, entryID: entryID) }
    }
}

extension View {
    /// Disables the edge-swipe back gesture, e.g. while an editor has unsaved changes.
    func popGestureBlocked(_ blocked: Bool) -> some View {
        modifier(PopGestureBlocker(blocked: blocked))
    }
}
