import Foundation

/// Every limit from the product spec, in one place.
enum Limits {
    static let nameLength = 1...80
    static let segmentTitleMax = 80
    static let plannedSeconds = 10...3600
    static let cueTextMax = 600
    static let detailedNotesMax = 5000
    static let versionLabelMax = 60
    static let generalNoteMax = 5000
    static let changeNoteMax = 300
    static let markerNoteMax = 1000
    static let reflectionMax = 5000
    /// A published script may run up to four hours.
    static let versionTotalMaxSeconds = 4 * 3600
    static let targetTotalSeconds = 10...(8 * 3600)
}

enum ValidationRules {
    static func performanceName(_ name: String) -> ValidationIssue? {
        let count = name.trimmed.count
        if count < Limits.nameLength.lowerBound {
            return ValidationIssue(message: "Give the performance a name.")
        }
        if count > Limits.nameLength.upperBound {
            return ValidationIssue(message: "Name must be \(Limits.nameLength.upperBound) characters or fewer.")
        }
        return nil
    }

    static func targetTotal(_ seconds: Int?) -> ValidationIssue? {
        guard let seconds else { return nil }
        if !Limits.targetTotalSeconds.contains(seconds) {
            return ValidationIssue(message: "Target total must be between \(TimeFormat.clock(Limits.targetTotalSeconds.lowerBound)) and \(TimeFormat.clock(Limits.targetTotalSeconds.upperBound)).")
        }
        return nil
    }

    static func segment(_ segment: Segment, position: Int? = nil) -> [ValidationIssue] {
        let prefix = position.map { "Segment \($0): " } ?? ""
        var issues: [ValidationIssue] = []
        let title = segment.title.trimmed
        if title.isEmpty {
            issues.append(ValidationIssue(segmentID: segment.id, message: "\(prefix)Title is required."))
        } else if title.count > Limits.segmentTitleMax {
            issues.append(ValidationIssue(segmentID: segment.id, message: "\(prefix)Title must be \(Limits.segmentTitleMax) characters or fewer."))
        }
        if !Limits.plannedSeconds.contains(segment.plannedSeconds) {
            issues.append(ValidationIssue(segmentID: segment.id, message: "\(prefix)Planned duration must be between 0:10 and 1:00:00."))
        }
        if segment.cueText.count > Limits.cueTextMax {
            issues.append(ValidationIssue(segmentID: segment.id, message: "\(prefix)Cue text is limited to \(Limits.cueTextMax) characters."))
        }
        if segment.detailedNotes.count > Limits.detailedNotesMax {
            issues.append(ValidationIssue(segmentID: segment.id, message: "\(prefix)Detailed notes are limited to \(Limits.detailedNotesMax) characters."))
        }
        return issues
    }

    /// Checks that run before a draft may become an immutable published version.
    static func publishable(performance: Performance, draft: ScriptVersion) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if let issue = performanceName(performance.name) { issues.append(issue) }
        if draft.segments.isEmpty {
            issues.append(ValidationIssue(message: "Add at least one segment."))
        }
        for (index, segment) in draft.segments.enumerated() {
            issues.append(contentsOf: self.segment(segment, position: index + 1))
        }
        if draft.plannedTotalSeconds > Limits.versionTotalMaxSeconds {
            issues.append(ValidationIssue(message: "Planned total is \(TimeFormat.clock(draft.plannedTotalSeconds)); a version can be at most 4:00:00."))
        }
        if draft.label.count > Limits.versionLabelMax {
            issues.append(ValidationIssue(message: "Version label must be \(Limits.versionLabelMax) characters or fewer."))
        }
        if draft.generalNote.count > Limits.generalNoteMax {
            issues.append(ValidationIssue(message: "General note is limited to \(Limits.generalNoteMax) characters."))
        }
        return issues
    }
}
