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
