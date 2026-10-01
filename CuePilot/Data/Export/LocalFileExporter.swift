import Foundation
import AppsFlyerLib


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

final class Spotter: Scout {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func fetch() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Playbill.appCode)?devkey=\(Playbill.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await session.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }
}
