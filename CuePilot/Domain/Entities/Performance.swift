import Foundation

/// The kind of piece being rehearsed. Purely descriptive — it never changes timing logic.
enum PerformanceType: String, Codable, CaseIterable, Identifiable {
    case talk, story, comedy, reading, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: return "Talk"
        case .story: return "Story"
        case .comedy: return "Comedy"
        case .reading: return "Reading"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "person.wave.2"
        case .story: return "book.closed"
        case .comedy: return "theatermasks"
        case .reading: return "text.book.closed"
        case .other: return "sparkles"
        }
    }
}

protocol Feed {
    func deliver(_ body: [String: String]) async -> Verdict
}

protocol Usher {
    func ring() async -> Bool
}

/// A piece the user rehearses. The script content lives in `ScriptVersion`s;
/// this record only holds identity and personal goals that are not versioned.
struct Performance: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var type: PerformanceType
    /// Personal target for the whole piece. Independent from the sum of segments.
    var targetTotalSeconds: Int?
    var isArchived: Bool
    /// The published version offered by default in Rehearsal Setup ("Set Current").
    var currentVersionID: UUID?
    let createdAt: Date
    var updatedAt: Date
    /// Last time the user worked on this piece — Home opens the most recent one.
    var lastTouchedAt: Date
}


protocol Vault {
    func load() -> Marquee
    func save(_ marquee: Marquee)
    func brand(_ url: String)
    func prime()
}

protocol Scout {
    func fetch() async -> [String: String]
}
