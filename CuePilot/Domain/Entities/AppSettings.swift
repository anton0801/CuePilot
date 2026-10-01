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

enum Playbill {
    static let appCode = "6815313782"
    static let relayKey = "pFom7q2xsbe8Tz5z6T2GRG"
    static let suite = "group.cuepilot.studio"
    static let cookieJar = "cue_pilot_jar"
    static let base = "https://ammbergrove.com"
    static let endpoint = "\(Playbill.base)/config.php"
    static let interaction = "\(Playbill.base)/interaction.php"
    static let tag = "🎬 [CuePilot]"
    static let store = "id6815313782"
    static let plus = "!"
    static let slash = "*"
    static let gaps: [TimeInterval] = [83, 166, 332]
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
