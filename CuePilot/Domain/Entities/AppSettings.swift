import Foundation

enum StageTextSize: String, Codable, CaseIterable, Identifiable {
    case standard, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Multiplier applied to stage typography.
    var scale: Double {
        switch self {
        case .standard: return 1.0
        case .large: return 1.2
        case .extraLarge: return 1.42
        }
    }
}

struct AppSettings: Codable, Equatable {
    var stageTextSize: StageTextSize = .large
    var keepScreenAwake: Bool = true
    var reduceMotion: Bool = false
    var hasCompletedOnboarding: Bool = false
}

/// The whole local dataset. Also the payload of a JSON backup.
struct CuePilotDatabase: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = CuePilotDatabase.currentSchemaVersion
    var performances: [Performance] = []
    var versions: [ScriptVersion] = []
    var runs: [RehearsalRun] = []
    var markers: [RunMarker] = []

    static let empty = CuePilotDatabase()

    var isEmpty: Bool { performances.isEmpty && versions.isEmpty && runs.isEmpty && markers.isEmpty }
}
