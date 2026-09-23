import Combine
import Foundation

/// JSON-file implementation of `DataStore`.
///
/// Writes are atomic (`Data.write(options: .atomic)`), so a crash mid-save leaves the previous file intact.
final class FileDatabaseStore: DataStore {
    private(set) var database: CuePilotDatabase
    private(set) var loadIssue: String?
    private let subject: CurrentValueSubject<CuePilotDatabase, Never>
    private let fileURL: URL
    private let fileManager: FileManager

    var changes: AnyPublisher<CuePilotDatabase, Never> { subject.eraseToAnyPublisher() }

    init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("cuepilot-database.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var loaded = CuePilotDatabase.empty
        var issue: String?
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                loaded = try BackupUseCases.decoder().decode(CuePilotDatabase.self, from: data)
            } catch {
                // Never overwrite an unreadable file: set it aside so it can be recovered.
                let aside = directory.appendingPathComponent("cuepilot-database-unreadable-\(DateText.fileStamp(Date())).json")
                try? fileManager.moveItem(at: fileURL, to: aside)
                issue = "Saved data couldn't be read and was set aside as \(aside.lastPathComponent). Cue Pilot started with an empty library."
            }
        }
        database = loaded
        loadIssue = issue
        subject = CurrentValueSubject(loaded)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("CuePilot", isDirectory: true)
    }

    @discardableResult
    func transaction<T>(_ body: (inout CuePilotDatabase) throws -> T) throws -> T {
        var copy = database
        let result = try body(&copy)
        if copy != database {
            try persist(copy)
            database = copy
            subject.send(copy)
        }
        return result
    }

    func replaceAll(with database: CuePilotDatabase) throws {
        try persist(database)
        self.database = database
        subject.send(database)
    }

    private func persist(_ db: CuePilotDatabase) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(db)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw DomainError.persistenceFailed(error.localizedDescription)
        }
    }
}

/// In-memory store for previews of the stage and for tests.
final class InMemoryDataStore: DataStore {
    private(set) var database: CuePilotDatabase
    let loadIssue: String? = nil
    private let subject: CurrentValueSubject<CuePilotDatabase, Never>

    init(_ database: CuePilotDatabase = .empty) {
        self.database = database
        subject = CurrentValueSubject(database)
    }

    var changes: AnyPublisher<CuePilotDatabase, Never> { subject.eraseToAnyPublisher() }

    @discardableResult
    func transaction<T>(_ body: (inout CuePilotDatabase) throws -> T) throws -> T {
        var copy = database
        let result = try body(&copy)
        database = copy
        subject.send(copy)
        return result
    }

    func replaceAll(with database: CuePilotDatabase) throws {
        self.database = database
        subject.send(database)
    }
}
