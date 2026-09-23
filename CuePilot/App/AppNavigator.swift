import SwiftUI

enum AppTab: Hashable {
    case performances, rehearse, runs
}

struct StagePresentation: Identifiable, Equatable {
    let runID: UUID
    var id: UUID { runID }
}

enum AppSheet: Identifiable, Equatable {
    case stagePreview(versionID: UUID?)

    var id: String {
        switch self {
        case let .stagePreview(versionID): return "preview-\(versionID?.uuidString ?? "sample")"
        }
    }
}

/// App-level navigation: tabs, one router per tab, and the full-screen Stage.
@MainActor
final class AppNavigator: ObservableObject {
    @Published var selectedTab: AppTab = .performances
    @Published var stage: StagePresentation?
    @Published var sheet: AppSheet?

    let performancesRouter = Router()
    let rehearseRouter = Router()
    let runsRouter = Router()

    var currentRouter: Router { router(for: selectedTab) }

    func router(for tab: AppTab) -> Router {
        switch tab {
        case .performances: return performancesRouter
        case .rehearse: return rehearseRouter
        case .runs: return runsRouter
        }
    }

    func setReduceMotion(_ value: Bool) {
        [performancesRouter, rehearseRouter, runsRouter].forEach { $0.reduceMotion = value }
    }

    /// Switches tab and shows exactly `routes` on it.
    func open(_ tab: AppTab, routes: [Route]) {
        selectedTab = tab
        router(for: tab).reset(to: routes)
    }

    func presentStage(runID: UUID) {
        stage = StagePresentation(runID: runID)
    }

    /// Stage closed. After a finished run the review opens on the current tab.
    func closeStage(reviewRunID: UUID?) {
        stage = nil
        guard let reviewRunID else { return }
        currentRouter.push(.review(runID: reviewRunID))
    }

    func resetAll() {
        [performancesRouter, rehearseRouter, runsRouter].forEach { $0.reset(to: []) }
        stage = nil
        sheet = nil
        selectedTab = .performances
    }
}
