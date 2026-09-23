import Foundation

struct RehearsalConfig: Equatable {
    var performanceID: UUID
    var versionID: UUID
    var mode: RunMode
    var startSegmentID: UUID?
    var includeOptional: Bool
}

/// What a configuration would rehearse — shown before Start so nothing is a surprise.
struct RehearsalPlan: Equatable {
    struct Item: Identifiable, Equatable {
        let segment: Segment
        let status: SegmentRunStatus
        var id: UUID { segment.id }
    }

    let version: ScriptVersion
    let items: [Item]
    let startSegmentID: UUID?

    var included: [Segment] { items.filter { $0.status == .pending || $0.status == .current }.map(\.segment) }
    var excludedOptional: [Segment] { items.filter { $0.status == .excluded }.map(\.segment) }
    var beforeStart: [Segment] { items.filter { $0.status == .beforeStart }.map(\.segment) }
    var plannedSeconds: Int { included.reduce(0) { $0 + $1.plannedSeconds } }
    var isPartial: Bool { !beforeStart.isEmpty }
    var isRunnable: Bool { !included.isEmpty }
    /// Segments that can be chosen as the start (included when optional ones are counted in).
    let startCandidates: [Segment]
}

/// Starting, checkpointing, recovering and finishing runs, plus markers and reflections.
final class RehearsalUseCases {
    private let store: DataStore
    private let clock: () -> Date

    init(store: DataStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    // MARK: Queries

    func liveRun() -> RehearsalRun? {
        store.database.runs.first(where: \.isLive)
    }

    func run(id: UUID) -> RehearsalRun? {
        store.database.runs.first { $0.id == id }
    }

    func runs(performanceID: UUID? = nil, versionID: UUID? = nil, mode: RunMode? = nil, includeLive: Bool = false) -> [RehearsalRun] {
        store.database.runs
            .filter { includeLive || !$0.isLive }
            .filter { performanceID == nil || $0.performanceID == performanceID }
            .filter { versionID == nil || $0.versionID == versionID }
            .filter { mode == nil || $0.mode == mode }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func markers(runID: UUID) -> [RunMarker] {
        store.database.markers
            .filter { $0.runID == runID }
            .sorted { $0.totalOffsetSeconds < $1.totalOffsetSeconds }
    }

    func plan(for config: RehearsalConfig) -> RehearsalPlan? {
        guard let version = store.database.versions.first(where: { $0.id == config.versionID }), version.isPublished else {
            return nil
        }
        let statuses = Self.initialStatuses(for: version.segments, includeOptional: config.includeOptional, startSegmentID: config.startSegmentID)
        let items = zip(version.segments, statuses).map { RehearsalPlan.Item(segment: $0, status: $1) }
        let candidates = version.segments.filter { config.includeOptional || !$0.isOptional }
        let effectiveStart = items.first { $0.status == .current }?.segment.id
        return RehearsalPlan(version: version, items: items, startSegmentID: effectiveStart, startCandidates: candidates)
    }

    // MARK: Lifecycle

    /// Confirm Start: takes one immutable snapshot of the script and creates exactly one session.
    @discardableResult
    func start(_ config: RehearsalConfig) throws -> RehearsalRun {
        let now = clock()
        return try store.transaction { db in
            if db.runs.contains(where: \.isLive) { throw DomainError.liveRunExists }
            guard let performance = db.performances.first(where: { $0.id == config.performanceID }) else {
                throw DomainError.notFound("Performance")
            }
            guard let version = db.versions.first(where: { $0.id == config.versionID && $0.performanceID == performance.id }) else {
                throw DomainError.notFound("Version")
            }
            guard version.isPublished else { throw DomainError.noPublishedVersion }
            let statuses = Self.initialStatuses(for: version.segments, includeOptional: config.includeOptional, startSegmentID: config.startSegmentID)
            guard let currentIndex = statuses.firstIndex(of: .current) else { throw DomainError.noSegmentsToRehearse }

            let snapshot = RunSnapshot(
                performanceName: performance.name,
                performanceType: performance.type,
                versionNumber: version.number,
                versionLabel: version.label,
                generalNote: version.generalNote,
                targetTotalSeconds: performance.targetTotalSeconds,
                segments: version.segments
            )
            let run = RehearsalRun(
                id: UUID(),
                performanceID: performance.id,
                versionID: version.id,
                mode: config.mode,
                includeOptional: config.includeOptional,
                startSegmentID: version.segments[currentIndex].id,
                snapshot: snapshot,
                startedAt: now,
                records: zip(version.segments, statuses).map {
                    SegmentRecord(segmentID: $0.id, status: $1, activeSeconds: 0, pausedSeconds: 0, advancedBy: nil)
                },
                currentIndex: currentIndex,
                phase: .running,
                outcome: nil,
                totalActiveSeconds: 0,
                totalPausedSeconds: 0,
                interruptionCount: 0,
                lastCheckpointAt: now,
                endedAt: nil,
                reflection: "",
                reflectionUpdatedAt: nil
            )
            db.runs.append(run)
            if let pIndex = db.performances.firstIndex(where: { $0.id == performance.id }) {
                db.performances[pIndex].lastTouchedAt = now
            }
            return run
        }
    }

    /// Saves the live state of a run coming from the engine (periodically and on every transition).
    func save(_ run: RehearsalRun) throws {
        try store.transaction { db in
            guard let index = db.runs.firstIndex(where: { $0.id == run.id }) else { throw DomainError.notFound("Run") }
            // A finished result is final: it can never be turned back into a live or different outcome.
            guard db.runs[index].isLive else { return }
            var updated = run
            updated.reflection = db.runs[index].reflection
            updated.reflectionUpdatedAt = db.runs[index].reflectionUpdatedAt
            db.runs[index] = updated
        }
    }

    /// Called at launch. A run saved as "running" means the app closed without passing through the
    /// background pause — restore the last checkpoint as Interrupted, adding no time for the gap.
    @discardableResult
    func recoverInterruptedRun() -> RehearsalRun? {
        guard let live = liveRun(), live.phase == .running else { return nil }
        return try? store.transaction { db in
            guard let index = db.runs.firstIndex(where: { $0.id == live.id }) else { return nil }
            db.runs[index].phase = .paused
            db.runs[index].interruptionCount += 1
            return db.runs[index]
        }
    }

    /// Ends the unfinished run without opening the stage (from Home, Setup or the Library).
    func endLiveRun() throws {
        let now = clock()
        try store.transaction { db in
            guard let index = db.runs.firstIndex(where: \.isLive) else { return }
            db.runs[index] = RunLifecycle.endedEarly(db.runs[index], at: now)
        }
    }

    /// Throws away the unfinished run and its markers.
    func discardLiveRun() throws {
        try store.transaction { db in
            guard let run = db.runs.first(where: \.isLive) else { return }
            db.runs.removeAll { $0.id == run.id }
            db.markers.removeAll { $0.runID == run.id }
        }
    }

    func deleteRun(id: UUID) throws {
        try store.transaction { db in
            guard let run = db.runs.first(where: { $0.id == id }) else { throw DomainError.notFound("Run") }
            if run.isLive { throw DomainError.runStillLive }
            db.runs.removeAll { $0.id == id }
            db.markers.removeAll { $0.runID == id }
        }
    }

    func saveReflection(runID: UUID, text: String) throws {
        if text.count > Limits.reflectionMax {
            throw DomainError.validation([ValidationIssue(message: "Reflection is limited to \(Limits.reflectionMax) characters.")])
        }
        let now = clock()
        try store.transaction { db in
            guard let index = db.runs.firstIndex(where: { $0.id == runID }) else { throw DomainError.notFound("Run") }
            db.runs[index].reflection = text
            db.runs[index].reflectionUpdatedAt = now
        }
    }

    // MARK: Markers

    @discardableResult
    func addMarker(runID: UUID, segmentID: UUID, segmentOffset: Double, totalOffset: Double, type: MarkerType = .review) throws -> RunMarker {
        let now = clock()
        let marker = RunMarker(
            id: UUID(), runID: runID, segmentID: segmentID,
            segmentOffsetSeconds: max(0, segmentOffset), totalOffsetSeconds: max(0, totalOffset),
            type: type, note: "", createdAt: now, updatedAt: now
        )
        try store.transaction { db in
            guard let run = db.runs.first(where: { $0.id == runID }) else { throw DomainError.notFound("Run") }
            guard run.snapshot.segments.contains(where: { $0.id == segmentID }) else { throw DomainError.notFound("Segment") }
            db.markers.append(marker)
        }
        return marker
    }

    /// Only type and note can change — the recorded time is fixed to the snapshot.
    func updateMarker(id: UUID, type: MarkerType, note: String) throws {
        if note.count > Limits.markerNoteMax {
            throw DomainError.validation([ValidationIssue(message: "Marker note is limited to \(Limits.markerNoteMax) characters.")])
        }
        let now = clock()
        try store.transaction { db in
            guard let index = db.markers.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("Marker") }
            db.markers[index].type = type
            db.markers[index].note = note.trimmed
            db.markers[index].updatedAt = now
        }
    }

    /// Deleting a marker never touches the run's timing.
    func deleteMarker(id: UUID) throws {
        try store.transaction { db in
            db.markers.removeAll { $0.id == id }
        }
    }

    // MARK: Helpers

    static func initialStatuses(for segments: [Segment], includeOptional: Bool, startSegmentID: UUID?) -> [SegmentRunStatus] {
        var statuses: [SegmentRunStatus] = segments.map { (!includeOptional && $0.isOptional) ? .excluded : .pending }
        let requestedStart = startSegmentID.flatMap { id in segments.firstIndex { $0.id == id } }
        let startIndex: Int? = {
            if let requestedStart, statuses[requestedStart] == .pending { return requestedStart }
            return statuses.firstIndex(of: .pending)
        }()
        guard let startIndex else { return statuses }
        for index in 0..<startIndex where statuses[index] == .pending {
            statuses[index] = .beforeStart
        }
        statuses[startIndex] = .current
        return statuses
    }
}
