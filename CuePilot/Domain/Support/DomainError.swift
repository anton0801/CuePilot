import Foundation

struct ValidationIssue: Identifiable, Equatable, Hashable {
    let id = UUID()
    /// Segment the issue belongs to, when it is segment-specific.
    var segmentID: UUID?
    var message: String

    static func == (lhs: ValidationIssue, rhs: ValidationIssue) -> Bool {
        lhs.segmentID == rhs.segmentID && lhs.message == rhs.message
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(segmentID)
        hasher.combine(message)
    }
}

@MainActor
protocol Act {
    func perform(_ stage: Stage) async -> Beat
}

struct RaiseAct: Act {
    func perform(_ stage: Stage) async -> Beat {
        if let push = stage.pendingPush() {
            return .settle(.bearing(push))
        }
        guard stage.hasData else { return .hold }
        if stage.needsRehearse { return .next(.rehearse) }
        return .next(.broadcast)
    }
}

struct RehearseAct: Act {
    func perform(_ stage: Stage) async -> Beat {
        await stage.rehearse()
        return .next(.broadcast)
    }
}

struct BroadcastAct: Act {
    func perform(_ stage: Stage) async -> Beat {
        .settle(await stage.airing())
    }
}

enum DomainError: LocalizedError, Equatable {
    case notFound(String)
    case validation([ValidationIssue])
    case liveRunExists
    case liveRunBlocksArchive
    case liveRunBlocksImport
    case noPublishedVersion
    case noSegmentsToRehearse
    case versionIsPublished
    case versionHasRuns
    case runStillLive
    case runsNotComparable(String)
    case confirmationMismatch
    case exportFailed(String)
    case backupInvalid([String])
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(what):
            return "\(what) could not be found. It may have been deleted."
        case let .validation(issues):
            return issues.map(\.message).joined(separator: "\n")
        case .liveRunExists:
            return "Another run is still in progress. Continue it, end it or discard it first — only one unfinished run can exist at a time."
        case .liveRunBlocksArchive:
            return "This performance has an unfinished run. End it early or discard it before archiving."
        case .liveRunBlocksImport:
            return "Replacing data is unavailable while a run is unfinished. End or discard the run first."
        case .noPublishedVersion:
            return "Publish a version before rehearsing. Runs are always tied to a published script."
        case .noSegmentsToRehearse:
            return "There is no segment to rehearse with these options."
        case .versionIsPublished:
            return "Published versions are locked. Edit a draft instead."
        case .versionHasRuns:
            return "This version has rehearsal results and can't be removed on its own. Archive the whole performance instead."
        case .runStillLive:
            return "This run is still in progress."
        case let .runsNotComparable(reason):
            return reason
        case .confirmationMismatch:
            return "Type DELETE in capital letters to confirm."
        case let .exportFailed(reason):
            return "Export failed: \(reason). Your script was not changed."
        case let .backupInvalid(problems):
            return "The backup can't be imported:\n" + problems.prefix(6).joined(separator: "\n")
        case let .persistenceFailed(reason):
            return "Couldn't save your data (\(reason)). Nothing was changed."
        }
    }
}
