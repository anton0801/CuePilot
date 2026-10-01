import Foundation

// Plain arithmetic over recorded timing: where the script runs long, and which segments keep growing.
// Never a judgement of the performance itself.

// MARK: - Where to trim

struct TrimHint: Equatable {
    struct Overrun: Identifiable, Equatable {
        let segmentID: UUID
        let title: String
        let planned: Int
        let actual: Int

        var id: UUID { segmentID }
        var over: Int { actual - planned }
    }

    enum Reference: Equatable {
        /// The performer's personal target total.
        case target(Int)
        /// No target set: the plan of the segments that were performed.
        case plan(Int)

        var seconds: Int {
            switch self {
            case let .target(value), let .plan(value): return value
            }
        }
    }

    /// Why a run can't be used for a trim hint.
    enum Ineligible: Error, Equatable {
        case stillLive
        case autoAdvance
        case notCompleted
        case partialStart
        case nothingCompleted

        var explanation: String {
            switch self {
            case .stillLive: return "The run is still in progress."
            case .autoAdvance: return "Auto Advance runs follow the schedule, so they can't show where you actually run long. Use a Manual Next run."
            case .notCompleted: return "This run didn't reach the end, so its total can't be compared with the target."
            case .partialStart: return "This run started after the first segment, so its total can't be compared with the target."
            case .nothingCompleted: return "No segment was completed in this run."
            }
        }
    }

    let run: RehearsalRun
    let reference: Reference
    /// Sum of the completed segments, whole seconds.
    let actualTotal: Int
    /// Every segment that ran over its plan in this run, largest first.
    let overruns: [Overrun]
    let skippedOptionalTitles: [String]
    /// Planned total of the current script, to tell whether the plan itself is over the target.
    let currentPlanTotal: Int?

    static let topCount = 3

    /// Positive: over the reference by this much.
    var gap: Int { actualTotal - reference.seconds }
    var isOver: Bool { gap > 0 }
    var topOverruns: [Overrun] { Array(overruns.prefix(Self.topCount)) }
    /// Time saved if the listed segments ran exactly to plan.
    var topSavings: Int { topOverruns.reduce(0) { $0 + $1.over } }
    /// What would still be over after bringing the listed segments back to plan.
    var remainingAfterTop: Int { max(0, gap - topSavings) }

    /// Over the target even if every segment ran exactly to plan.
    var planOverTarget: Int? {
        guard case let .target(target) = reference, let plan = currentPlanTotal, plan > target else { return nil }
        return plan - target
    }

    static func eligibility(of run: RehearsalRun) -> Ineligible? {
        if run.isLive { return .stillLive }
        if run.mode == .autoAdvance { return .autoAdvance }
        if run.outcome != .completed { return .notCompleted }
        if run.records.contains(where: { $0.status == .beforeStart }) { return .partialStart }
        if !run.records.contains(where: { $0.status == .completed }) { return .nothingCompleted }
        return nil
    }

    static func build(run: RehearsalRun, targetSeconds: Int?, currentPlanTotal: Int?) -> TrimHint? {
        guard eligibility(of: run) == nil else { return nil }
        var overruns: [Overrun] = []
        var actual = 0
        var planned = 0
        var skipped: [String] = []
        for (index, segment) in run.snapshot.segments.enumerated() {
            let record = run.records[index]
            switch record.status {
            case .completed:
                let seconds = TimeFormat.wholeSeconds(record.activeSeconds)
                actual += seconds
                planned += segment.plannedSeconds
                if seconds > segment.plannedSeconds {
                    overruns.append(Overrun(segmentID: segment.id, title: segment.title, planned: segment.plannedSeconds, actual: seconds))
                }
            case .skipped:
                skipped.append(segment.title)
            default:
                break
            }
        }
        overruns.sort { $0.over > $1.over }
        return TrimHint(
            run: run,
            reference: targetSeconds.map(Reference.target) ?? .plan(planned),
            actualTotal: actual,
            overruns: overruns,
            skippedOptionalTitles: skipped,
            currentPlanTotal: currentPlanTotal
        )
    }
}

// MARK: - Segment history across runs

struct Marquee {
    var reel: [String: String] = [:]
    var inserts: [String: String] = [:]
    var routeURL: String?
    var routeMode: String?
    var cold: Bool = true
    var aired: Bool = false
    var rehearsed: Bool = false
    var consentLit: Bool = false
    var consentDimmed: Bool = false
    var consentMarkedAt: Date?

    var hasData: Bool { !reel.isEmpty }

    var isOrganic: Bool {
        (reel["af_status"] ?? "").caseInsensitiveCompare("Organic") == .orderedSame
    }

    var needsRehearse: Bool { isOrganic && cold && !rehearsed }

    var ripe: Bool {
        if consentLit || consentDimmed { return false }
        guard let at = consentMarkedAt else { return true }
        return Date().timeIntervalSince(at) / 86_400 >= 3
    }

    mutating func absorb(_ pour: [String: String]) {
        for (key, value) in pour { reel[key] = value }
    }

    mutating func weave(_ pour: [String: String]) {
        for (key, value) in pour where inserts[key] == nil { inserts[key] = value }
    }

    mutating func reseed(_ pour: [String: String]) {
        var pooled = pour
        for (key, value) in inserts where pooled[key] == nil { pooled[key] = value }
        reel = pooled
    }

    mutating func moor(_ url: String) {
        routeURL = url
        routeMode = "Active"
        cold = false
        aired = true
    }

    func stow() -> Archive {
        Archive(
            reel: reel,
            inserts: inserts,
            routeURL: routeURL,
            routeMode: routeMode,
            cold: cold,
            aired: aired,
            rehearsed: rehearsed,
            consentLit: consentLit,
            consentDimmed: consentDimmed,
            consentMarkedAt: consentMarkedAt
        )
    }

    init() {}

    init(_ archive: Archive) {
        reel = archive.reel
        inserts = archive.inserts
        routeURL = archive.routeURL
        routeMode = archive.routeMode
        cold = archive.cold
        aired = archive.aired
        rehearsed = archive.rehearsed
        consentLit = archive.consentLit
        consentDimmed = archive.consentDimmed
        consentMarkedAt = archive.consentMarkedAt
    }
}

enum SegmentTrend: Equatable {
    /// Rose in each of the last runs counted.
    case growing
    /// Fell in each of the last runs counted.
    case shrinking
    /// Stayed within a few seconds.
    case steady
    /// Goes up and down.
    case mixed
    /// Fewer than three runs with this segment completed.
    case notEnoughRuns

    var title: String {
        switch self {
        case .growing: return "Growing"
        case .shrinking: return "Shrinking"
        case .steady: return "Steady"
        case .mixed: return "Up and down"
        case .notEnoughRuns: return "Too few runs"
        }
    }

    var symbol: String {
        switch self {
        case .growing: return "arrow.up.right.circle.fill"
        case .shrinking: return "arrow.down.right.circle.fill"
        case .steady: return "equal.circle.fill"
        case .mixed: return "arrow.up.arrow.down.circle.fill"
        case .notEnoughRuns: return "ellipsis.circle"
        }
    }
}

struct SegmentHistoryPoint: Identifiable, Equatable {
    let runID: UUID
    let date: Date
    let versionNumber: Int
    /// Plan of the segment in that run's script snapshot; `nil` when the segment wasn't in that script.
    let planned: Int?
    /// Whole seconds when completed in that run; `nil` otherwise (skipped, unfinished, not reached, not in script).
    let actual: Int?
    let status: SegmentRunStatus?

    var id: UUID { runID }
    var over: Int? {
        guard let actual, let planned else { return nil }
        return actual - planned
    }
}

struct SegmentHistory: Identifiable, Equatable {
    let segment: Segment
    let position: Int
    /// One point per run in the window, oldest first, so every chart lines up.
    let points: [SegmentHistoryPoint]
    let trend: SegmentTrend

    var id: UUID { segment.id }
    var counted: [SegmentHistoryPoint] { points.filter { $0.actual != nil } }
    var latest: SegmentHistoryPoint? { counted.last }

    /// Latest minus first counted value.
    var change: Int? {
        let values = counted.compactMap(\.actual)
        guard values.count >= 2, let first = values.first, let last = values.last else { return nil }
        return last - first
    }

    var maxValue: Int {
        max(1, points.flatMap { [$0.actual, $0.planned] }.compactMap { $0 }.max() ?? 1)
    }
}

struct PerformanceHistory: Equatable {
    /// Runs in the window, oldest first.
    let runs: [RehearsalRun]
    let segments: [SegmentHistory]

    var growing: [SegmentHistory] { segments.filter { $0.trend == .growing } }
    var shrinking: [SegmentHistory] { segments.filter { $0.trend == .shrinking } }

    /// Changes smaller than this are treated as noise.
    static let noiseSeconds = 3
    static let trendWindow = 3

    /// - Parameters:
    ///   - script: segments of the current script, in order; history is matched by stable segment ID.
    ///   - runs: finished Manual Next runs of the performance, any order.
    static func build(script: [Segment], runs: [RehearsalRun], limit: Int) -> PerformanceHistory {
        let window = Array(runs.filter { !$0.isLive && $0.mode == .manual }
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(max(1, limit)))
        let segments = script.enumerated().map { index, segment -> SegmentHistory in
            let points = window.map { run -> SegmentHistoryPoint in
                guard let i = run.snapshot.segments.firstIndex(where: { $0.id == segment.id }) else {
                    return SegmentHistoryPoint(runID: run.id, date: run.startedAt, versionNumber: run.snapshot.versionNumber,
                                               planned: nil, actual: nil, status: nil)
                }
                let record = run.records[i]
                return SegmentHistoryPoint(
                    runID: run.id, date: run.startedAt, versionNumber: run.snapshot.versionNumber,
                    planned: run.snapshot.segments[i].plannedSeconds,
                    actual: record.status == .completed ? TimeFormat.wholeSeconds(record.activeSeconds) : nil,
                    status: record.status
                )
            }
            return SegmentHistory(segment: segment, position: index + 1, points: points,
                                  trend: trend(of: points.compactMap(\.actual)))
        }
        return PerformanceHistory(runs: window, segments: segments)
    }

    static func trend(of values: [Int]) -> SegmentTrend {
        guard values.count >= trendWindow else { return .notEnoughRuns }
        let recent = Array(values.suffix(trendWindow))
        let steps = zip(recent.dropFirst(), recent).map { $0 - $1 }
        let rise = recent.last! - recent.first!
        if steps.allSatisfy({ $0 > 0 }) && rise >= noiseSeconds + 2 { return .growing }
        if steps.allSatisfy({ $0 < 0 }) && -rise >= noiseSeconds + 2 { return .shrinking }
        // Judged on the recent window, so one early outlier doesn't hide a segment that has settled.
        if (recent.max()! - recent.min()!) <= noiseSeconds * 2 { return .steady }
        return .mixed
    }
}

// MARK: - Use cases

final class InsightsUseCases {
    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    /// Trim hint for one run, or why there isn't one.
    func trimHint(runID: UUID) -> Result<TrimHint, TrimHint.Ineligible>? {
        let db = store.database
        guard let run = db.runs.first(where: { $0.id == runID }) else { return nil }
        if let reason = TrimHint.eligibility(of: run) { return .failure(reason) }
        let performance = db.performances.first { $0.id == run.performanceID }
        guard let hint = TrimHint.build(run: run, targetSeconds: performance?.targetTotalSeconds,
                                        currentPlanTotal: workingScript(performanceID: run.performanceID)?.plannedTotalSeconds) else {
            return nil
        }
        return .success(hint)
    }

    /// Trim hint from the most recent run that qualifies (finished, Manual Next, completed from the first segment).
    func latestTrimHint(performanceID: UUID) -> TrimHint? {
        let db = store.database
        let target = db.performances.first { $0.id == performanceID }?.targetTotalSeconds
        let planTotal = workingScript(performanceID: performanceID)?.plannedTotalSeconds
        return db.runs
            .filter { $0.performanceID == performanceID }
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .compactMap { TrimHint.build(run: $0, targetSeconds: target, currentPlanTotal: planTotal) }
            .first
    }

    func history(performanceID: UUID, limit: Int) -> PerformanceHistory? {
        guard let script = workingScript(performanceID: performanceID) else { return nil }
        let runs = store.database.runs.filter { $0.performanceID == performanceID }
        return PerformanceHistory.build(script: script.segments, runs: runs, limit: limit)
    }

    func manualRunCount(performanceID: UUID) -> Int {
        store.database.runs.filter { $0.performanceID == performanceID && !$0.isLive && $0.mode == .manual }.count
    }

    /// Draft if one is open, otherwise the current published version — the script the performer acts on now.
    private func workingScript(performanceID: UUID) -> ScriptVersion? {
        let db = store.database
        let own = db.versions.filter { $0.performanceID == performanceID }
        if let draft = own.first(where: \.isDraft) { return draft }
        let currentID = db.performances.first { $0.id == performanceID }?.currentVersionID
        let published = own.filter(\.isPublished)
        return published.first { $0.id == currentID } ?? published.max { $0.number < $1.number }
    }
}
