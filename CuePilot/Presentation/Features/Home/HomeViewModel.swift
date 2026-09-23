import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    struct LiveRunInfo: Equatable {
        let run: RehearsalRun
        let position: Int
        let total: Int
        var wasInterrupted: Bool { run.interruptionCount > 0 }
    }

    @Published private(set) var summary: PerformanceSummary?
    @Published private(set) var liveRun: LiveRunInfo?
    @Published private(set) var hasAnyPerformance = false
    @Published private(set) var activeCount = 0
    @Published private(set) var tip = ""
    @Published var alert: AlertMessage?

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer) {
        self.container = container
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        let performances = container.performances
        hasAnyPerformance = !container.store.database.performances.isEmpty
        activeCount = performances.performances(archived: false).count
        summary = performances.currentPerformance().map(performances.summary(for:))
        if let run = container.rehearsals.liveRun() {
            let included = run.includedIndices
            let position = run.currentIndex.flatMap { included.firstIndex(of: $0) }.map { $0 + 1 } ?? included.count
            liveRun = LiveRunInfo(run: run, position: position, total: included.count)
        } else {
            liveRun = nil
        }
        tip = FlickTips.tip(summary: summary, liveRun: liveRun?.run, lastReview: lastReview())
    }

    private func lastReview() -> RunReview? {
        guard let run = summary?.lastRun else { return nil }
        return RunReview.build(run: run, markers: container.rehearsals.markers(runID: run.id))
    }

    func endLiveRun() {
        do { try container.rehearsals.endLiveRun() } catch { alert = AlertMessage(error) }
    }

    func discardLiveRun() {
        do { try container.rehearsals.discardLiveRun() } catch { alert = AlertMessage(error) }
    }
}

/// Short, factual hints from Flick. Never an assessment of the performance itself.
enum FlickTips {
    static func tip(summary: PerformanceSummary?, liveRun: RehearsalRun?, lastReview: RunReview?) -> String {
        if let liveRun {
            return liveRun.interruptionCount > 0
                ? "Your last run was cut off. It's saved at its last checkpoint — resume when you're back in position."
                : "Your run is paused right where you left it. Resume when you're ready."
        }
        guard let summary else {
            return "Start with the shape, not the words: name your piece and split it into a few clear segments."
        }
        if summary.segmentCount == 0 {
            return "Add a first segment with a short cue — a few words you can read at a glance."
        }
        if summary.currentVersion == nil {
            return "Publish the draft to lock this version. Runs always remember the script they used."
        }
        if summary.runCount == 0 {
            return "Try a Manual Next run: tap Next when each part is really over."
        }
        if let overrun = lastReview?.largestOverrun {
            return "Last run, “\(overrun.segment.title)” went \(TimeFormat.delta(overrun.deviation)) over plan. Compare runs to see if it keeps growing."
        }
        if summary.runCount == 1 {
            return "One more run of the same version and you can compare them segment by segment."
        }
        return "Drop a marker whenever something feels long — sort them out after the run."
    }
}
