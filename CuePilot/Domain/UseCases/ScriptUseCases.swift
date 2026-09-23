import Foundation

/// A version row in Script Versions.
struct VersionListItem: Identifiable, Equatable {
    let version: ScriptVersion
    let isCurrent: Bool
    let linkedRunCount: Int

    var id: UUID { version.id }
}

/// Drafts, publishing and the version history of one performance.
///
/// Published versions are never mutated. Any edit made while no draft exists first creates a draft
/// copied from the current published version, keeping segment IDs stable.
final class ScriptUseCases {
    private let store: DataStore
    private let clock: () -> Date

    init(store: DataStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    // MARK: Queries

    func versions(performanceID: UUID) -> [ScriptVersion] {
        store.database.versions
            .filter { $0.performanceID == performanceID }
            .sorted { $0.number > $1.number }
    }

    func version(id: UUID) -> ScriptVersion? {
        store.database.versions.first { $0.id == id }
    }

    func draft(performanceID: UUID) -> ScriptVersion? {
        store.database.versions.first { $0.performanceID == performanceID && $0.isDraft }
    }

    func publishedVersions(performanceID: UUID) -> [ScriptVersion] {
        versions(performanceID: performanceID).filter(\.isPublished)
    }

    func currentPublished(performanceID: UUID) -> ScriptVersion? {
        let published = publishedVersions(performanceID: performanceID)
        let currentID = store.database.performances.first { $0.id == performanceID }?.currentVersionID
        return published.first { $0.id == currentID } ?? published.first
    }

    /// Draft if one is open, otherwise the current published version.
    func workingVersion(performanceID: UUID) -> ScriptVersion? {
        draft(performanceID: performanceID) ?? currentPublished(performanceID: performanceID)
    }

    func versionItems(performanceID: UUID) -> [VersionListItem] {
        let currentID = currentPublished(performanceID: performanceID)?.id
        let runs = store.database.runs
        return versions(performanceID: performanceID).map { version in
            VersionListItem(
                version: version,
                isCurrent: version.id == currentID,
                linkedRunCount: runs.filter { $0.versionID == version.id }.count
            )
        }
    }

    func linkedRunCount(versionID: UUID) -> Int {
        store.database.runs.filter { $0.versionID == versionID }.count
    }

    /// Number the next draft would get.
    func nextVersionNumber(performanceID: UUID) -> Int {
        (store.database.versions.filter { $0.performanceID == performanceID }.map(\.number).max() ?? 0) + 1
    }

    // MARK: Draft editing

    /// Returns the open draft, creating one from the current published version if necessary.
    @discardableResult
    func ensureDraft(performanceID: UUID) throws -> ScriptVersion {
        if let draft = draft(performanceID: performanceID) { return draft }
        return try store.transaction { db in
            try Self.makeDraft(in: &db, performanceID: performanceID, basedOn: nil, now: clock())
        }
    }

    func updateDraftDetails(performanceID: UUID, label: String, generalNote: String) throws {
        var issues: [ValidationIssue] = []
        if label.trimmed.count > Limits.versionLabelMax {
            issues.append(ValidationIssue(message: "Version label must be \(Limits.versionLabelMax) characters or fewer."))
        }
        if generalNote.count > Limits.generalNoteMax {
            issues.append(ValidationIssue(message: "General note is limited to \(Limits.generalNoteMax) characters."))
        }
        if !issues.isEmpty { throw DomainError.validation(issues) }
        try mutateDraft(performanceID: performanceID) { draft in
            draft.label = label.trimmed
            draft.generalNote = generalNote
        }
    }

    /// Inserts or updates a segment in the draft. New segments are appended, or placed after `insertAfter`.
    func saveSegment(_ segment: Segment, performanceID: UUID, insertAfter: UUID? = nil) throws {
        var cleaned = segment
        cleaned.title = segment.title.trimmed
        let issues = ValidationRules.segment(cleaned)
        if !issues.isEmpty { throw DomainError.validation(issues) }
        try mutateDraft(performanceID: performanceID) { draft in
            if let index = draft.segments.firstIndex(where: { $0.id == cleaned.id }) {
                draft.segments[index] = cleaned
            } else if let anchor = insertAfter, let anchorIndex = draft.segments.firstIndex(where: { $0.id == anchor }) {
                draft.segments.insert(cleaned, at: anchorIndex + 1)
            } else {
                draft.segments.append(cleaned)
            }
        }
    }

    /// Copies a segment right after itself with a new stable ID.
    @discardableResult
    func duplicateSegment(id: UUID, performanceID: UUID) throws -> Segment {
        guard let source = workingVersion(performanceID: performanceID)?.segment(withID: id) else {
            throw DomainError.notFound("Segment")
        }
        let copy = Segment(id: UUID(), title: String("\(source.title) (copy)".prefix(Limits.segmentTitleMax)),
                       plannedSeconds: source.plannedSeconds, cueText: source.cueText,
                       detailedNotes: source.detailedNotes, isOptional: source.isOptional)
        try saveSegment(copy, performanceID: performanceID, insertAfter: id)
        return copy
    }

    /// Removes a segment from the draft only. Published snapshots and past runs keep it.
    func deleteSegment(id: UUID, performanceID: UUID) throws {
        try mutateDraft(performanceID: performanceID) { draft in
            draft.segments.removeAll { $0.id == id }
        }
    }

    func moveSegments(performanceID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) throws {
        try mutateDraft(performanceID: performanceID) { draft in
            draft.segments.moveElements(fromOffsets: source, toOffset: destination)
        }
    }

    func reorderSegments(performanceID: UUID, orderedIDs: [UUID]) throws {
        try mutateDraft(performanceID: performanceID) { draft in
            let lookup = Dictionary(draft.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let reordered = orderedIDs.compactMap { lookup[$0] }
            guard reordered.count == draft.segments.count else { return }
            draft.segments = reordered
        }
    }

    // MARK: Publishing & history

    func publishIssues(performanceID: UUID) -> [ValidationIssue] {
        guard let performance = store.database.performances.first(where: { $0.id == performanceID }) else {
            return [ValidationIssue(message: "Performance not found.")]
        }
        guard let draft = draft(performanceID: performanceID) else {
            return [ValidationIssue(message: "There is no draft to publish.")]
        }
        return ValidationRules.publishable(performance: performance, draft: draft)
    }

    /// Freezes the draft into an immutable published version and makes it current.
    @discardableResult
    func publishDraft(performanceID: UUID, changeNote: String) throws -> ScriptVersion {
        let issues = publishIssues(performanceID: performanceID)
        if !issues.isEmpty { throw DomainError.validation(issues) }
        if changeNote.count > Limits.changeNoteMax {
            throw DomainError.validation([ValidationIssue(message: "Change note is limited to \(Limits.changeNoteMax) characters.")])
        }
        let now = clock()
        return try store.transaction { db in
            guard let index = db.versions.firstIndex(where: { $0.performanceID == performanceID && $0.isDraft }),
                  let pIndex = db.performances.firstIndex(where: { $0.id == performanceID }) else {
                throw DomainError.notFound("Draft")
            }
            db.versions[index].status = .published
            db.versions[index].publishedAt = now
            db.versions[index].updatedAt = now
            db.versions[index].changeNote = changeNote.trimmed
            db.performances[pIndex].currentVersionID = db.versions[index].id
            db.performances[pIndex].updatedAt = now
            db.performances[pIndex].lastTouchedAt = now
            return db.versions[index]
        }
    }

    /// Starts a new draft from any version. An existing draft is replaced only when `replacingDraft` is true.
    @discardableResult
    func createDraft(from versionID: UUID, replacingDraft: Bool) throws -> ScriptVersion {
        guard let base = version(id: versionID) else { throw DomainError.notFound("Version") }
        if base.isDraft { return base }
        return try store.transaction { db in
            if db.versions.contains(where: { $0.performanceID == base.performanceID && $0.isDraft }) {
                guard replacingDraft else {
                    throw DomainError.validation([ValidationIssue(message: "A draft is already open. Replace it or keep editing it.")])
                }
                db.versions.removeAll { $0.performanceID == base.performanceID && $0.isDraft }
            }
            return try Self.makeDraft(in: &db, performanceID: base.performanceID, basedOn: versionID, now: clock())
        }
    }

    /// Changes the default for new rehearsals. Past runs keep the version they used.
    func setCurrent(versionID: UUID) throws {
        guard let version = version(id: versionID), version.isPublished else { throw DomainError.notFound("Published version") }
        let now = clock()
        try store.transaction { db in
            guard let index = db.performances.firstIndex(where: { $0.id == version.performanceID }) else {
                throw DomainError.notFound("Performance")
            }
            db.performances[index].currentVersionID = versionID
            db.performances[index].updatedAt = now
        }
    }

    /// Drafts can never have runs, so an open draft can always be discarded.
    func discardDraft(performanceID: UUID) throws {
        try store.transaction { db in
            guard let draft = db.versions.first(where: { $0.performanceID == performanceID && $0.isDraft }) else {
                throw DomainError.notFound("Draft")
            }
            if db.runs.contains(where: { $0.versionID == draft.id }) { throw DomainError.versionHasRuns }
            db.versions.removeAll { $0.id == draft.id }
        }
    }

    // MARK: Internals

    private func mutateDraft(performanceID: UUID, _ change: (inout ScriptVersion) throws -> Void) throws {
        let now = clock()
        try store.transaction { db in
            if !db.versions.contains(where: { $0.performanceID == performanceID && $0.isDraft }) {
                try Self.makeDraft(in: &db, performanceID: performanceID, basedOn: nil, now: now)
            }
            guard let index = db.versions.firstIndex(where: { $0.performanceID == performanceID && $0.isDraft }) else {
                throw DomainError.notFound("Draft")
            }
            try change(&db.versions[index])
            db.versions[index].updatedAt = now
            if let pIndex = db.performances.firstIndex(where: { $0.id == performanceID }) {
                db.performances[pIndex].lastTouchedAt = now
                db.performances[pIndex].updatedAt = now
            }
        }
    }

    @discardableResult
    private static func makeDraft(in db: inout CuePilotDatabase, performanceID: UUID, basedOn versionID: UUID?, now: Date) throws -> ScriptVersion {
        guard let performance = db.performances.first(where: { $0.id == performanceID }) else {
            throw DomainError.notFound("Performance")
        }
        let own = db.versions.filter { $0.performanceID == performanceID }
        let base: ScriptVersion? = {
            if let versionID { return own.first { $0.id == versionID } }
            let published = own.filter(\.isPublished)
            return published.first { $0.id == performance.currentVersionID } ?? published.max { $0.number < $1.number }
        }()
        let draft = ScriptVersion(
            id: UUID(),
            performanceID: performanceID,
            number: (own.map(\.number).max() ?? 0) + 1,
            label: "",
            generalNote: base?.generalNote ?? "",
            changeNote: "",
            status: .draft,
            segments: base?.segments ?? [],
            createdAt: now,
            updatedAt: now,
            publishedAt: nil,
            basedOnVersionID: base?.id
        )
        db.versions.append(draft)
        return draft
    }
}
