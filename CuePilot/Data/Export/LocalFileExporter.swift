import Foundation

/// Writes shareable files into a temporary folder, and safety backups into Documents.
final class LocalFileExporter: FileExporting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func write(data: Data, fileName: String) throws -> URL {
        let folder = fileManager.temporaryDirectory.appendingPathComponent("CuePilotExports", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Kept in Documents/Safety Backups so it is visible in the Files app and survives restarts.
    func writeSafetyBackup(data: Data, fileName: String) throws -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folder = documents.appendingPathComponent("Safety Backups", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
