import Foundation

// MARK: - Review of one run

struct ReviewRow: Identifiable, Equatable {
    let position: Int
    let segment: Segment
    let record: SegmentRecord
    let markers: [RunMarker]

    var id: UUID { segment.id }

    /// Whole seconds of the closed segment.
    var actualSeconds: Int { TimeFormat.wholeSeconds(record.activeSeconds) }

    /// actual − planned. Only meaningful for a completed segment.
    var deviation: Int { actualSeconds - segment.plannedSeconds }

    var isExceeded: Bool { deviation > 0 }
}

struct RunReview: Equatable {
    let run: RehearsalRun
    let completed: [ReviewRow]
    let skipped: [ReviewRow]
    let unfinished: [ReviewRow]
    let notReached: [ReviewRow]
    let excluded: [ReviewRow]
    let beforeStart: [ReviewRow]
    let markers: [RunMarker]

    var plannedForCompleted: Int { completed.reduce(0) { $0 + $1.segment.plannedSeconds } }
    var actualForCompleted: Int { completed.reduce(0) { $0 + $1.actualSeconds } }

    /// Sum of deviations over completed segments — Manual runs only, where it reflects real timing.
    var manualDeviationTotal: Int? {
        guard run.mode == .manual, !completed.isEmpty else { return nil }
        return completed.reduce(0) { $0 + $1.deviation }
    }

    /// Auto Advance: segments that ran exactly on the schedule vs. ones the performer moved on from early.
    var autoOnSchedule: [ReviewRow] { completed.filter { $0.record.advancedBy == .autoSchedule } }
    var autoAdvancedEarly: [ReviewRow] { completed.filter { $0.record.advancedBy != .autoSchedule } }

    var exceededCount: Int { run.mode == .manual ? completed.filter(\.isExceeded).count : 0 }

    /// The completed segment that ran furthest over plan — the first candidate for trimming.
    var largestOverrun: ReviewRow? {
        guard run.mode == .manual else { return nil }
        return completed.filter(\.isExceeded).max { $0.deviation < $1.deviation }
    }

    static func build(run: RehearsalRun, markers: [RunMarker]) -> RunReview {
        var buckets: [SegmentRunStatus: [ReviewRow]] = [:]
        for (index, segment) in run.snapshot.segments.enumerated() {
            let record = run.records[index]
            let row = ReviewRow(
                position: index + 1,
                segment: segment,
                record: record,
                markers: markers.filter { $0.segmentID == segment.id }
            )
            buckets[record.status, default: []].append(row)
        }
        // A live run viewed mid-way: its current segment is treated as unfinished, pending as not reached.
        return RunReview(
            run: run,
            completed: buckets[.completed] ?? [],
            skipped: buckets[.skipped] ?? [],
            unfinished: (buckets[.unfinished] ?? []) + (buckets[.current] ?? []),
            notReached: (buckets[.notReached] ?? []) + (buckets[.pending] ?? []),
            excluded: buckets[.excluded] ?? [],
            beforeStart: buckets[.beforeStart] ?? [],
            markers: markers
        )
    }
}

// MARK: - Comparison of two runs

enum ComparisonCell: Equatable {
    case completed(actual: Int, planned: Int)
    case notCounted(SegmentRunStatus)

    var actual: Int? {
        if case let .completed(actual, _) = self { return actual }
        return nil
    }
}

struct ComparisonRow: Identifiable, Equatable {
    let segmentID: UUID
    let title: String
    let positionA: Int
    let positionB: Int
    let a: ComparisonCell
    let b: ComparisonCell
    let changes: [SegmentChange]
    let markersA: [RunMarker]
    let markersB: [RunMarker]

    var id: UUID { segmentID }

    /// B − A. Only when the segment was completed in both runs.
    var difference: Int? {
        guard let actualA = a.actual, let actualB = b.actual else { return nil }
        return actualB - actualA
    }

    var isChanged: Bool { !changes.isEmpty }
}

struct UnmatchedSegment: Identifiable, Equatable {
    let segment: Segment
    let cell: ComparisonCell
    var id: UUID { segment.id }
}

struct RunComparison: Equatable {
    let runA: RehearsalRun
    let runB: RehearsalRun
    let rows: [ComparisonRow]
    let onlyInA: [UnmatchedSegment]
    let onlyInB: [UnmatchedSegment]

    var sameVersion: Bool { runA.versionID == runB.versionID }

    /// Rows that enter the total: completed in both runs.
    var countedRows: [ComparisonRow] { rows.filter { $0.difference != nil } }

    var totalDifference: Int? {
        let counted = countedRows
        guard !counted.isEmpty else { return nil }
        return counted.reduce(0) { $0 + ($1.difference ?? 0) }
    }

    /// The matched segment that grew the most from A to B.
    var biggestGrowth: ComparisonRow? {
        countedRows.filter { ($0.difference ?? 0) > 0 }.max { ($0.difference ?? 0) < ($1.difference ?? 0) }
    }

    var maxActual: Int {
        let values = rows.flatMap { [$0.a.actual, $0.b.actual] }.compactMap { $0 }
        return max(values.max() ?? 1, 1)
    }

    enum Eligibility: Equatable {
        case ok
        case warningDifferentVersions
        case blocked(String)
    }

    static func eligibility(_ a: RehearsalRun, _ b: RehearsalRun) -> Eligibility {
        if a.id == b.id { return .blocked("Choose two different runs.") }
        if a.isLive || b.isLive { return .blocked("Unfinished runs can't be compared yet.") }
        if a.performanceID != b.performanceID { return .blocked("Runs of different performances can't be compared.") }
        if a.mode != b.mode {
            return .blocked("Manual Next and Auto Advance runs measure different things and can't be compared together.")
        }
        if a.versionID != b.versionID { return .warningDifferentVersions }
        return .ok
    }

    static func build(a: RehearsalRun, b: RehearsalRun, markersA: [RunMarker], markersB: [RunMarker]) -> RunComparison {
        func cell(_ run: RehearsalRun, _ index: Int) -> ComparisonCell {
            let record = run.records[index]
            let segment = run.snapshot.segments[index]
            if record.status == .completed {
                return .completed(actual: TimeFormat.wholeSeconds(record.activeSeconds), planned: segment.plannedSeconds)
            }
            return .notCounted(record.status)
        }

        let indexA = Dictionary(a.snapshot.segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let indexB = Dictionary(b.snapshot.segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Matched by stable segment ID, ordered as in run B's script.
        var rows: [ComparisonRow] = []
        var onlyInB: [UnmatchedSegment] = []
        for (bIndex, segmentB) in b.snapshot.segments.enumerated() {
            guard let aIndex = indexA[segmentB.id] else {
                onlyInB.append(UnmatchedSegment(segment: segmentB, cell: cell(b, bIndex)))
                continue
            }
            let segmentA = a.snapshot.segments[aIndex]
            rows.append(ComparisonRow(
                segmentID: segmentB.id,
                title: segmentB.title,
                positionA: aIndex + 1,
                positionB: bIndex + 1,
                a: cell(a, aIndex),
                b: cell(b, bIndex),
                changes: segmentA.changes(comparedTo: segmentB),
                markersA: markersA.filter { $0.segmentID == segmentB.id },
                markersB: markersB.filter { $0.segmentID == segmentB.id }
            ))
        }
        let onlyInA = a.snapshot.segments.enumerated()
            .filter { indexB[$0.element.id] == nil }
            .map { UnmatchedSegment(segment: $0.element, cell: cell(a, $0.offset)) }

        return RunComparison(runA: a, runB: b, rows: rows, onlyInA: onlyInA, onlyInB: onlyInB)
    }

    /// Default pair: the two latest Manual runs of one version (preferring the given one),
    /// falling back to the two latest runs sharing a mode.
    static func defaultPair(from runs: [RehearsalRun], preferredVersionID: UUID?) -> (a: RehearsalRun, b: RehearsalRun)? {
        let finished = runs.filter { !$0.isLive }.sorted { $0.startedAt > $1.startedAt }
        let manual = finished.filter { $0.mode == .manual }
        let byVersion = Dictionary(grouping: manual, by: \.versionID)
        if let preferredVersionID, let list = byVersion[preferredVersionID], list.count >= 2 {
            return (list[1], list[0])
        }
        if let newest = manual.first(where: { (byVersion[$0.versionID]?.count ?? 0) >= 2 }),
           let list = byVersion[newest.versionID] {
            return (list[1], list[0])
        }
        for mode in [RunMode.manual, .autoAdvance] {
            let sameMode = finished.filter { $0.mode == mode }
            if sameMode.count >= 2 { return (sameMode[1], sameMode[0]) }
        }
        return nil
    }
}
