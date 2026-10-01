import Foundation

/// One part of a performance. The `id` is stable across versions until the user deletes the segment,
/// which is what lets runs of different versions be compared segment by segment.
struct Segment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var plannedSeconds: Int
    var cueText: String
    var detailedNotes: String
    var isOptional: Bool

    static func blank(plannedSeconds: Int = 60) -> Segment {
        Segment(id: UUID(), title: "", plannedSeconds: plannedSeconds, cueText: "", detailedNotes: "", isOptional: false)
    }

    /// Fields that matter when deciding whether a matched segment "Changed" between two script snapshots.
    func changes(comparedTo other: Segment) -> [SegmentChange] {
        var result: [SegmentChange] = []
        if title.trimmed != other.title.trimmed { result.append(.title) }
        if plannedSeconds != other.plannedSeconds { result.append(.planned(from: plannedSeconds, to: other.plannedSeconds)) }
        if cueText.trimmed != other.cueText.trimmed { result.append(.cue) }
        if isOptional != other.isOptional { result.append(.optionality) }
        return result
    }
}

enum SegmentChange: Equatable {
    case title
    case planned(from: Int, to: Int)
    case cue
    case optionality

    var label: String {
        switch self {
        case .title: return "Title"
        case let .planned(from, to): return "Plan \(TimeFormat.clock(from)) → \(TimeFormat.clock(to))"
        case .cue: return "Cue"
        case .optionality: return "Optional flag"
        }
    }
}

enum Marks {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let att = "cp_att_status"
    static let primed = "cp_primed"
    static let route = "cp_route_url"
    static let mode = "cp_route_mode"
    static let grant = "cp_consent_locked"
    static let deny = "cp_consent_drifted"
    static let stamp = "cp_consent_mapped_at"
    static let blob = "cp_marquee_blob"
}

enum VersionStatus: String, Codable {
    case draft, published
}

/// A script version. Drafts are editable; published versions are immutable and are what runs are tied to.
struct ScriptVersion: Identifiable, Codable, Equatable {
    let id: UUID
    let performanceID: UUID
    var number: Int
    var label: String
    var generalNote: String
    var changeNote: String
    var status: VersionStatus
    var segments: [Segment]
    let createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?
    var basedOnVersionID: UUID?

    var isDraft: Bool { status == .draft }
    var isPublished: Bool { status == .published }

    var plannedTotalSeconds: Int { segments.reduce(0) { $0 + $1.plannedSeconds } }

    var displayName: String {
        let trimmed = label.trimmed
        return trimmed.isEmpty ? "Version \(number)" : "v\(number) · \(trimmed)"
    }

    var shortName: String { "v\(number)" }

    func segment(withID id: UUID) -> Segment? { segments.first { $0.id == id } }
}

extension Notification.Name {
    static let onair = Notification.Name("ConversionDataReceived")
    static let slate = Notification.Name("deeplink_values")
    static let standby = Notification.Name("LoadTempURL")
}
