import Foundation

enum RunMode: String, Codable, CaseIterable, Identifiable {
    /// The performer taps Next when a segment is really over. Measures actual duration.
    case manual
    /// Segments switch on their planned duration. Schedule practice, not a measurement of speech.
    case autoAdvance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual Next"
        case .autoAdvance: return "Auto Advance"
        }
    }

    var shortTitle: String {
        switch self {
        case .manual: return "Manual"
        case .autoAdvance: return "Auto"
        }
    }

    var explanation: String {
        switch self {
        case .manual:
            return "You tap Next when a segment is done. Going over plan is flagged but never skips ahead — the run measures your real timing."
        case .autoAdvance:
            return "Segments switch on their planned duration. This is practice against a schedule — it does not measure when you actually finished speaking."
        }
    }

    var symbol: String {
        switch self {
        case .manual: return "hand.tap"
        case .autoAdvance: return "timer"
        }
    }
}

/// Whether a live run's clock is moving. `nil` once the run is finished.
enum RunPhase: String, Codable {
    case running, paused
}

enum RunOutcome: String, Codable, CaseIterable {
    case completed, endedEarly, interrupted

    var title: String {
        switch self {
        case .completed: return "Completed"
        case .endedEarly: return "Ended Early"
        case .interrupted: return "Interrupted"
        }
    }

    var symbol: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .endedEarly: return "stop.circle.fill"
        case .interrupted: return "bolt.horizontal.circle.fill"
        }
    }
}

enum Fumble: Error {
    case dropped
    case dark404
    case cancelled
    case cooldown(TimeInterval)
    case static_

    var sealed: Bool {
        switch self {
        case .dark404, .cancelled: return true
        default: return false
        }
    }

    var cool: TimeInterval? {
        if case .cooldown(let seconds) = self { return seconds }
        return nil
    }
}

enum SegmentRunStatus: String, Codable {
    /// Still ahead in a live run.
    case pending
    /// The segment on stage right now.
    case current
    /// Closed by Next / Finish / Auto Advance. The only status whose time counts.
    case completed
    /// Optional segment skipped during the run.
    case skipped
    /// Optional segment left out in Rehearsal Setup.
    case excluded
    /// Before the chosen start segment.
    case beforeStart
    /// The run ended before this segment began.
    case notReached
    /// On stage when the run was ended; never closed.
    case unfinished

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .current: return "On Stage"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .excluded: return "Excluded"
        case .beforeStart: return "Before Start"
        case .notReached: return "Not Reached"
        case .unfinished: return "Unfinished"
        }
    }
}

/// How a completed segment was closed — used to explain Auto Advance runs honestly.
enum AdvanceTrigger: String, Codable {
    case manualNext, autoSchedule, finish
}

struct SegmentRecord: Codable, Equatable {
    let segmentID: UUID
    var status: SegmentRunStatus
    /// Active (unpaused) seconds spent on this segment.
    var activeSeconds: Double
    /// Paused seconds while this segment was on stage (foreground only).
    var pausedSeconds: Double
    var advancedBy: AdvanceTrigger?
}

/// Immutable copy of the script taken at Confirm Start.
struct RunSnapshot: Codable, Equatable {
    let performanceName: String
    let performanceType: PerformanceType
    let versionNumber: Int
    let versionLabel: String
    let generalNote: String
    let targetTotalSeconds: Int?
    let segments: [Segment]

    var versionDisplayName: String {
        let trimmed = versionLabel.trimmed
        return trimmed.isEmpty ? "Version \(versionNumber)" : "v\(versionNumber) · \(trimmed)"
    }
}

struct RehearsalRun: Identifiable, Codable, Equatable {
    let id: UUID
    let performanceID: UUID
    let versionID: UUID
    let mode: RunMode
    let includeOptional: Bool
    let startSegmentID: UUID
    let snapshot: RunSnapshot
    let startedAt: Date

    /// Parallel to `snapshot.segments`.
    var records: [SegmentRecord]
    /// Index into `snapshot.segments` of the segment on stage. `nil` once finished.
    var currentIndex: Int?
    /// `nil` once finished.
    var phase: RunPhase?
    /// `nil` while the run is live.
    var outcome: RunOutcome?

    var totalActiveSeconds: Double
    var totalPausedSeconds: Double
    /// How many times the run was recovered after the app closed unexpectedly.
    var interruptionCount: Int
    var lastCheckpointAt: Date
    var endedAt: Date?

    var reflection: String
    var reflectionUpdatedAt: Date?

    var isLive: Bool { outcome == nil }

    /// True when the run does not cover the whole included script.
    var isPartial: Bool {
        if records.contains(where: { $0.status == .beforeStart }) { return true }
        if let outcome, outcome != .completed { return true }
        return false
    }

    var currentSegment: Segment? {
        guard let currentIndex, snapshot.segments.indices.contains(currentIndex) else { return nil }
        return snapshot.segments[currentIndex]
    }

    func record(for segmentID: UUID) -> SegmentRecord? {
        records.first { $0.segmentID == segmentID }
    }

    /// Indices that take part in this run (not excluded, not before start), in script order.
    var includedIndices: [Int] {
        records.indices.filter { records[$0].status != .excluded && records[$0].status != .beforeStart }
    }

    var completedCount: Int { records.filter { $0.status == .completed }.count }
}

enum MarkerType: String, Codable, CaseIterable, Identifiable {
    case review, shorten, clarify, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "Review"
        case .shorten: return "Shorten"
        case .clarify: return "Clarify"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .review: return "eye"
        case .shorten: return "scissors"
        case .clarify: return "text.bubble"
        case .other: return "bookmark"
        }
    }
}

/// A manual bookmark the performer drops during a run. Never an automatically detected "mistake".
struct RunMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let runID: UUID
    /// Segment from the run's snapshot; the time below is relative to that snapshot and never re-mapped.
    let segmentID: UUID
    let segmentOffsetSeconds: Double
    let totalOffsetSeconds: Double
    var type: MarkerType
    var note: String
    let createdAt: Date
    var updatedAt: Date
}
