import Combine
import Foundation

/// Composition root: builds the Data layer implementations and hands them to the Domain use cases.
@MainActor
final class AppContainer: ObservableObject {
    let store: DataStore
    let settingsRepository: SettingsRepository
    let performances: PerformanceUseCases
    let scripts: ScriptUseCases
    let rehearsals: RehearsalUseCases
    let exports: ExportUseCases
    let backups: BackupUseCases
    let insights: InsightsUseCases

    @Published private(set) var settings: AppSettings
    /// Set at launch when an unfinished run had to be recovered from its last checkpoint.
    @Published var recoveredRunID: UUID?
    @Published var launchIssue: String?

    private var cancellables: Set<AnyCancellable> = []

    init(store: DataStore, settingsRepository: SettingsRepository, files: FileExporting = LocalFileExporter(),
         renderer: ExportRendering = PDFExportRenderer()) {
        self.store = store
        self.settingsRepository = settingsRepository
        performances = PerformanceUseCases(store: store)
        scripts = ScriptUseCases(store: store)
        rehearsals = RehearsalUseCases(store: store)
        exports = ExportUseCases(store: store, renderer: renderer, files: files)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        backups = BackupUseCases(store: store, files: files, appVersion: version)
        insights = InsightsUseCases(store: store)
        settings = settingsRepository.settings
        launchIssue = store.loadIssue

        settingsRepository.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.settings = $0 }
            .store(in: &cancellables)

        recoveredRunID = rehearsals.recoverInterruptedRun()?.id
    }

    static func live() -> AppContainer {
        AppContainer(
            store: FileDatabaseStore(directory: FileDatabaseStore.defaultDirectory()),
            settingsRepository: UserDefaultsSettingsRepository()
        )
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        settingsRepository.update(change)
    }

    /// Publisher views use to refresh whenever the dataset changes.
    var databaseChanges: AnyPublisher<CuePilotDatabase, Never> {
        store.changes.receive(on: RunLoop.main).eraseToAnyPublisher()
    }
}


final class Overlay {

    private var main: [AnyHashable: Any] = [:]
    private var insert: [AnyHashable: Any] = [:]
    private var pending: DispatchWorkItem?
    private let ready: ([AnyHashable: Any]) -> Void

    init(ready: @escaping ([AnyHashable: Any]) -> Void) {
        self.ready = ready
    }

    func base(_ payload: [AnyHashable: Any]) {
        main = payload
        pending?.cancel()
        pending = nil
        if insert.isEmpty == false {
            mix()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.mix() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func patch(_ payload: [AnyHashable: Any]) {
        insert = payload
        pending?.cancel()
        pending = nil
        if main.isEmpty == false { mix() }
    }

    private func mix() {
        pending?.cancel()
        pending = nil
        var out = main
        for (key, value) in insert {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)"
            if out[tag] == nil { out[tag] = value }
        }
        ready(out)
    }
}
