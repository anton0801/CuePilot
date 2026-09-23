import Combine
import Foundation

/// Gateway to the local dataset. Implemented in the Data layer.
///
/// Every write goes through `transaction`, which applies the change to a copy, persists it and only then
/// publishes it — so a failed save leaves both the file and the in-memory state untouched.
protocol DataStore: AnyObject {
    var database: CuePilotDatabase { get }
    var changes: AnyPublisher<CuePilotDatabase, Never> { get }
    /// A problem found while loading the saved file (for example an unreadable file that was set aside).
    var loadIssue: String? { get }

    @discardableResult
    func transaction<T>(_ body: (inout CuePilotDatabase) throws -> T) throws -> T
    func replaceAll(with database: CuePilotDatabase) throws
}

protocol SettingsRepository: AnyObject {
    var settings: AppSettings { get }
    var changes: AnyPublisher<AppSettings, Never> { get }
    func update(_ change: (inout AppSettings) -> Void)
    func reset(keepingOnboarding: Bool)
}

/// Writes files that leave the app (exports, backups). Implemented in the Data layer.
protocol FileExporting {
    func write(data: Data, fileName: String) throws -> URL
    func writeSafetyBackup(data: Data, fileName: String) throws -> URL
}

/// Turns a structured export document into shareable formats. Implemented in the Data layer.
protocol ExportRendering {
    func pdf(for document: ExportDocument) throws -> Data
    func csv(for table: ExportTable) -> Data
}
