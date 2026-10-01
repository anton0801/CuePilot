import Foundation

/// The JSON backup file format.
struct BackupEnvelope: Codable {
    static let formatIdentifier = "cuepilot.backup"

    var format: String = BackupEnvelope.formatIdentifier
    var exportedAt: Date
    var appVersion: String
    var database: CuePilotDatabase
}

struct BackupPreview: Equatable {
    let exportedAt: Date
    let appVersion: String
    let performances: Int
    let archivedPerformances: Int
    let versions: Int
    let runs: Int
    let markers: Int
    let hasUnfinishedRun: Bool
}

struct BackupInspection {
    let preview: BackupPreview?
    let problems: [String]
    let database: CuePilotDatabase?

    var isValid: Bool { problems.isEmpty && database != nil }
}

@MainActor
final class Stage {

    var marquee: Marquee
    let vault: Vault
    let scout: Scout
    let feed: Feed
    let usher: Usher

    private var cued = false

    init(studio: Studio) {
        vault = studio.vault
        scout = studio.scout
        feed = studio.feed
        usher = studio.usher
        marquee = studio.vault.load()
        cued = true
    }

    func ensureCued() {
        guard !cued else { return }
        marquee = vault.load()
        cued = true
    }

    var hasData: Bool { marquee.hasData }
    var needsRehearse: Bool { marquee.needsRehearse }

    func pendingPush() -> String? {
        let value = UserDefaults.standard.string(forKey: Marks.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }

    func absorb(_ pour: [String: String]) {
        marquee.absorb(pour)
        vault.save(marquee)
    }

    func weave(_ pour: [String: String]) {
        marquee.weave(pour)
        vault.save(marquee)
    }

    func save() {
        vault.save(marquee)
    }

    func rehearse() async {
        marquee.rehearsed = true
        vault.save(marquee)

        try? await Task.sleep(nanoseconds: 5_000_000_000)

        if marquee.aired == false {
            let fresh = await scout.fetch()
            if fresh.isEmpty == false {
                marquee.reseed(fresh)
                vault.save(marquee)
            }
        }
    }

    func airing() async -> Verdict {
        await feed.deliver(marquee.reel)
    }

    func moor(_ url: String) {
        marquee.moor(url)
        vault.save(marquee)
        vault.brand(url)
        vault.prime()
        UserDefaults.standard.removeObject(forKey: Marks.pushURL)
    }

    func savedRoute() -> String? {
        if let mirror = UserDefaults.standard.string(forKey: Marks.route), mirror.isEmpty == false { return mirror }
        if let held = marquee.routeURL, held.isEmpty == false { return held }
        return nil
    }

    func pin(_ url: String) {
        UserDefaults.standard.set(url, forKey: Marks.route)
    }
}


/// Export, validate, import and wipe the local dataset.
final class BackupUseCases {
    private let store: DataStore
    private let files: FileExporting
    private let appVersion: String
    private let clock: () -> Date

    init(store: DataStore, files: FileExporting, appVersion: String, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.files = files
        self.appVersion = appVersion
        self.clock = clock
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func exportBackup() throws -> URL {
        let envelope = BackupEnvelope(exportedAt: clock(), appVersion: appVersion, database: store.database)
        let data = try Self.encoder().encode(envelope)
        return try files.write(data: data, fileName: "CuePilot-Backup-\(DateText.fileStamp(clock())).json")
    }

    /// Step 1–2 of Import: decode and validate every relation. Nothing is changed.
    func inspect(data: Data) -> BackupInspection {
        let envelope: BackupEnvelope
        do {
            envelope = try Self.decoder().decode(BackupEnvelope.self, from: data)
        } catch {
            return BackupInspection(preview: nil, problems: ["This file isn't a readable Cue Pilot backup."], database: nil)
        }
        guard envelope.format == BackupEnvelope.formatIdentifier else {
            return BackupInspection(preview: nil, problems: ["This file isn't a Cue Pilot backup."], database: nil)
        }
        let db = envelope.database
        let problems = BackupValidator.problems(in: db)
        let preview = BackupPreview(
            exportedAt: envelope.exportedAt,
            appVersion: envelope.appVersion,
            performances: db.performances.filter { !$0.isArchived }.count,
            archivedPerformances: db.performances.filter(\.isArchived).count,
            versions: db.versions.count,
            runs: db.runs.count,
            markers: db.markers.count,
            hasUnfinishedRun: db.runs.contains(where: \.isLive)
        )
        return BackupInspection(preview: preview, problems: problems, database: problems.isEmpty ? db : nil)
    }

    var canReplace: Bool { !store.database.runs.contains(where: \.isLive) }

    /// Steps 4–5: save a safety copy of the current data, then replace. Any failure leaves the data untouched.
    @discardableResult
    func replace(with database: CuePilotDatabase) throws -> URL {
        guard canReplace else { throw DomainError.liveRunBlocksImport }
        let problems = BackupValidator.problems(in: database)
        guard problems.isEmpty else { throw DomainError.backupInvalid(problems) }
        let safety = BackupEnvelope(exportedAt: clock(), appVersion: appVersion, database: store.database)
        let safetyURL = try files.writeSafetyBackup(
            data: try Self.encoder().encode(safety),
            fileName: "CuePilot-Before-Import-\(DateText.fileStamp(clock())).json"
        )
        var incoming = database
        // An unfinished run inside a backup is restored paused and flagged, never still "running".
        for index in incoming.runs.indices where incoming.runs[index].isLive && incoming.runs[index].phase == .running {
            incoming.runs[index].phase = .paused
            incoming.runs[index].interruptionCount += 1
        }
        try store.replaceAll(with: incoming)
        return safetyURL
    }

    func deleteAllData(confirmation: String) throws {
        guard confirmation == "DELETE" else { throw DomainError.confirmationMismatch }
        try store.replaceAll(with: .empty)
    }
}

/// Referential and range checks for an incoming dataset.
enum BackupValidator {
    static func problems(in db: CuePilotDatabase) -> [String] {
        var problems: [String] = []
        if db.schemaVersion > CuePilotDatabase.currentSchemaVersion {
            problems.append("The backup was made by a newer version of Cue Pilot (schema \(db.schemaVersion)).")
        }

        func duplicates<T: Hashable>(_ values: [T]) -> Bool { Set(values).count != values.count }
        if duplicates(db.performances.map(\.id)) { problems.append("Duplicate performance IDs.") }
        if duplicates(db.versions.map(\.id)) { problems.append("Duplicate version IDs.") }
        if duplicates(db.runs.map(\.id)) { problems.append("Duplicate run IDs.") }
        if duplicates(db.markers.map(\.id)) { problems.append("Duplicate marker IDs.") }

        let performances = Dictionary(db.performances.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let versions = Dictionary(db.versions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for performance in db.performances {
            if ValidationRules.performanceName(performance.name) != nil {
                problems.append("Performance “\(performance.name.prefix(30))” has an invalid name.")
            }
            let own = db.versions.filter { $0.performanceID == performance.id }
            if own.filter(\.isDraft).count > 1 {
                problems.append("“\(performance.name)” has more than one draft.")
            }
            if duplicates(own.map(\.number)) {
                problems.append("“\(performance.name)” has two versions with the same number.")
            }
            if let current = performance.currentVersionID {
                guard let version = versions[current], version.performanceID == performance.id, version.isPublished else {
                    problems.append("“\(performance.name)” points to a current version that doesn't exist or isn't published.")
                    continue
                }
            }
        }

        for version in db.versions {
            guard performances[version.performanceID] != nil else {
                problems.append("Version \(version.number) belongs to a missing performance.")
                continue
            }
            if duplicates(version.segments.map(\.id)) {
                problems.append("Version \(version.number) repeats a segment ID.")
            }
            if version.isPublished {
                if version.segments.isEmpty { problems.append("Published version \(version.number) has no segments.") }
                if version.plannedTotalSeconds > Limits.versionTotalMaxSeconds {
                    problems.append("Published version \(version.number) is longer than 4 hours.")
                }
                for segment in version.segments where !ValidationRules.segment(segment).isEmpty {
                    problems.append("Version \(version.number) has an invalid segment “\(segment.title.prefix(30))”.")
                    break
                }
            }
        }

        let liveRuns = db.runs.filter(\.isLive)
        if liveRuns.count > 1 { problems.append("More than one unfinished run.") }

        for run in db.runs {
            let label = "Run of \(DateText.day(run.startedAt))"
            guard performances[run.performanceID] != nil else {
                problems.append("\(label) belongs to a missing performance.")
                continue
            }
            guard let version = versions[run.versionID], version.performanceID == run.performanceID, version.isPublished else {
                problems.append("\(label) points to a missing or unpublished version.")
                continue
            }
            if run.records.count != run.snapshot.segments.count
                || zip(run.records, run.snapshot.segments).contains(where: { $0.segmentID != $1.id }) {
                problems.append("\(label) has timing records that don't match its script snapshot.")
            }
            if duplicates(run.snapshot.segments.map(\.id)) {
                problems.append("\(label) repeats a segment ID in its snapshot.")
            }
            if run.isLive {
                if run.phase == nil || run.currentIndex.map({ !run.records.indices.contains($0) }) ?? true {
                    problems.append("\(label) is unfinished but has no valid current segment.")
                }
            } else if run.phase != nil || run.currentIndex != nil {
                problems.append("\(label) is finished but still has a live state.")
            }
            if run.totalActiveSeconds < 0 || run.totalPausedSeconds < 0 || run.records.contains(where: { $0.activeSeconds < 0 || $0.pausedSeconds < 0 }) {
                problems.append("\(label) has negative times.")
            }
        }

        let runs = Dictionary(db.runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for marker in db.markers {
            guard let run = runs[marker.runID] else {
                problems.append("A marker belongs to a missing run.")
                continue
            }
            if !run.snapshot.segments.contains(where: { $0.id == marker.segmentID }) {
                problems.append("A marker points to a segment outside its run's snapshot.")
            }
        }

        // Keep the list readable.
        var seen = Set<String>()
        return problems.filter { seen.insert($0).inserted }
    }
}
