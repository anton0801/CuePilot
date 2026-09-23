import Foundation

/// What Home and the Library show about one performance.
struct PerformanceSummary: Identifiable, Equatable {
    let performance: Performance
    let currentVersion: ScriptVersion?
    let draft: ScriptVersion?
    let latestVersion: ScriptVersion?
    let lastRun: RehearsalRun?
    let liveRun: RehearsalRun?
    let runCount: Int

    var id: UUID { performance.id }

    /// The version whose segments represent "the current script": the draft if one is open, otherwise the current published one.
    var workingVersion: ScriptVersion? { draft ?? currentVersion }

    var segmentCount: Int { workingVersion?.segments.count ?? 0 }

    /// `nil` means "Not Set Up" — there are no segments yet.
    var plannedTotalSeconds: Int? {
        guard let version = workingVersion, !version.segments.isEmpty else { return nil }
        return version.plannedTotalSeconds
    }

    var canRehearse: Bool { currentVersion != nil }
}

enum LiveRunResolution {
    case endEarly
    case discard
}

final class PerformanceUseCases {
    private let store: DataStore
    private let clock: () -> Date

    init(store: DataStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    // MARK: Queries

    func performance(id: UUID) -> Performance? {
        store.database.performances.first { $0.id == id }
    }

    func performances(archived: Bool, matching query: String = "") -> [Performance] {
        let needle = query.trimmed.lowercased()
        return store.database.performances
            .filter { $0.isArchived == archived }
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) || $0.type.title.lowercased().contains(needle) }
            .sorted { $0.lastTouchedAt > $1.lastTouchedAt }
    }

    /// The most recently touched active performance — what Home opens.
    func currentPerformance() -> Performance? {
        store.database.performances
            .filter { !$0.isArchived }
            .max { $0.lastTouchedAt < $1.lastTouchedAt }
    }

    func summary(for performance: Performance) -> PerformanceSummary {
        let db = store.database
        let versions = db.versions.filter { $0.performanceID == performance.id }
        let published = versions.filter(\.isPublished)
        let current = published.first { $0.id == performance.currentVersionID }
            ?? published.max { $0.number < $1.number }
        let runs = db.runs.filter { $0.performanceID == performance.id }
        let finished = runs.filter { !$0.isLive }
        return PerformanceSummary(
            performance: performance,
            currentVersion: current,
            draft: versions.first(where: \.isDraft),
            latestVersion: versions.max { $0.number < $1.number },
            lastRun: finished.max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) },
            liveRun: runs.first(where: \.isLive),
            runCount: finished.count
        )
    }

    // MARK: Commands

    /// Creates the performance together with its first draft.
    @discardableResult
    func create(name: String, type: PerformanceType, targetTotalSeconds: Int?, versionLabel: String, generalNote: String) throws -> Performance {
        try validateDetails(name: name, target: targetTotalSeconds)
        let now = clock()
        let performance = Performance(
            id: UUID(), name: name.trimmed, type: type, targetTotalSeconds: targetTotalSeconds,
            isArchived: false, currentVersionID: nil, createdAt: now, updatedAt: now, lastTouchedAt: now
        )
        let draft = ScriptVersion(
            id: UUID(), performanceID: performance.id, number: 1, label: versionLabel.trimmed,
            generalNote: generalNote, changeNote: "", status: .draft, segments: [],
            createdAt: now, updatedAt: now, publishedAt: nil, basedOnVersionID: nil
        )
        try store.transaction { db in
            db.performances.append(performance)
            db.versions.append(draft)
        }
        return performance
    }

    func updateDetails(id: UUID, name: String, type: PerformanceType, targetTotalSeconds: Int?) throws {
        try validateDetails(name: name, target: targetTotalSeconds)
        let now = clock()
        try store.transaction { db in
            guard let index = db.performances.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("Performance") }
            db.performances[index].name = name.trimmed
            db.performances[index].type = type
            db.performances[index].targetTotalSeconds = targetTotalSeconds
            db.performances[index].updatedAt = now
            db.performances[index].lastTouchedAt = now
        }
    }

    /// Marks the performance as the one being worked on, so Home opens it next time.
    func touch(id: UUID) {
        guard let current = performance(id: id), !current.isArchived else { return }
        if abs(current.lastTouchedAt.timeIntervalSince(clock())) < 2 { return }
        try? store.transaction { db in
            guard let index = db.performances.firstIndex(where: { $0.id == id }) else { return }
            db.performances[index].lastTouchedAt = clock()
        }
    }

    /// Copies the current segments into a brand-new performance. Runs, markers and reflections are not copied.
    @discardableResult
    func duplicateStructure(id: UUID) throws -> Performance {
        guard let source = performance(id: id) else { throw DomainError.notFound("Performance") }
        let summary = summary(for: source)
        let now = clock()
        let baseName = "\(source.name) Copy"
        let copy = Performance(
            id: UUID(), name: String(baseName.prefix(Limits.nameLength.upperBound)), type: source.type,
            targetTotalSeconds: source.targetTotalSeconds, isArchived: false, currentVersionID: nil,
            createdAt: now, updatedAt: now, lastTouchedAt: now
        )
        let segments = (summary.workingVersion?.segments ?? []).map { segment in
            Segment(id: UUID(), title: segment.title, plannedSeconds: segment.plannedSeconds, cueText: segment.cueText,
                    detailedNotes: segment.detailedNotes, isOptional: segment.isOptional)
        }
        let draft = ScriptVersion(
            id: UUID(), performanceID: copy.id, number: 1, label: "",
            generalNote: summary.workingVersion?.generalNote ?? "", changeNote: "Duplicated from \(source.name)",
            status: .draft, segments: segments, createdAt: now, updatedAt: now, publishedAt: nil, basedOnVersionID: nil
        )
        try store.transaction { db in
            db.performances.append(copy)
            db.versions.append(draft)
        }
        return copy
    }

    /// Archiving keeps all history. An unfinished run must be resolved first.
    func archive(id: UUID, resolvingLiveRun resolution: LiveRunResolution? = nil) throws {
        let now = clock()
        try store.transaction { db in
            guard let index = db.performances.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("Performance") }
            if let liveIndex = db.runs.firstIndex(where: { $0.performanceID == id && $0.isLive }) {
                switch resolution {
                case nil:
                    throw DomainError.liveRunBlocksArchive
                case .endEarly:
                    db.runs[liveIndex] = RunLifecycle.endedEarly(db.runs[liveIndex], at: now)
                case .discard:
                    let runID = db.runs[liveIndex].id
                    db.runs.remove(at: liveIndex)
                    db.markers.removeAll { $0.runID == runID }
                }
            }
            db.performances[index].isArchived = true
            db.performances[index].updatedAt = now
        }
    }

    func restore(id: UUID) throws {
        let now = clock()
        try store.transaction { db in
            guard let index = db.performances.firstIndex(where: { $0.id == id }) else { throw DomainError.notFound("Performance") }
            db.performances[index].isArchived = false
            db.performances[index].updatedAt = now
            db.performances[index].lastTouchedAt = now
        }
    }

    private func validateDetails(name: String, target: Int?) throws {
        let issues = [ValidationRules.performanceName(name), ValidationRules.targetTotal(target)].compactMap { $0 }
        if !issues.isEmpty { throw DomainError.validation(issues) }
    }
}

/// Run transitions that happen outside Stage Mode, from the saved record only (no live clock).
enum RunLifecycle {
    static func endedEarly(_ run: RehearsalRun, at date: Date) -> RehearsalRun {
        var run = run
        guard run.isLive else { return run }
        if let index = run.currentIndex {
            run.records[index].status = .unfinished
        }
        for index in run.records.indices where run.records[index].status == .pending {
            run.records[index].status = .notReached
        }
        run.currentIndex = nil
        run.phase = nil
        run.outcome = run.interruptionCount > 0 ? .interrupted : .endedEarly
        run.endedAt = date
        run.lastCheckpointAt = date
        return run
    }
}
