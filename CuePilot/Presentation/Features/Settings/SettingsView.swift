import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var liveRunExists = false
    @Published private(set) var archivedCount = 0
    @Published private(set) var totals = (performances: 0, runs: 0, markers: 0)
    @Published var share: ShareItem?
    @Published var alert: AlertMessage?
    @Published var inspection: BackupInspection?
    @Published var showImportPreview = false

    let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer) {
        self.container = container
        container.databaseChanges
            .sink { [weak self] db in
                self?.liveRunExists = db.runs.contains(where: \.isLive)
                self?.archivedCount = db.performances.filter(\.isArchived).count
                self?.totals = (db.performances.count, db.runs.count, db.markers.count)
            }
            .store(in: &cancellables)
    }

    func exportBackup() {
        do {
            share = ShareItem(urls: [try container.backups.exportBackup()])
        } catch {
            alert = AlertMessage(title: "Backup failed", error)
        }
    }

    /// Import step 1–3: read, validate, preview. Nothing changes yet.
    func inspectImport(result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                inspection = container.backups.inspect(data: data)
                showImportPreview = true
            } catch {
                alert = AlertMessage(title: "Couldn't read the file", error)
            }
        case let .failure(error):
            alert = AlertMessage(title: "Couldn't open the file", error)
        }
    }

    /// Import step 4–5: safety backup of the current data, then replace.
    func replaceWithImport() -> Bool {
        guard let database = inspection?.database else { return false }
        do {
            let safety = try container.backups.replace(with: database)
            showImportPreview = false
            inspection = nil
            alert = AlertMessage(title: "Backup restored",
                                 message: "Your previous data was saved first as “\(safety.lastPathComponent)” in Files › On My iPhone › Cue Pilot › Safety Backups.")
            return true
        } catch {
            alert = AlertMessage(title: "Import failed — nothing was changed", error)
            return false
        }
    }

    func deleteAll(confirmation: String) -> Bool {
        do {
            try container.backups.deleteAllData(confirmation: confirmation)
            container.settingsRepository.reset(keepingOnboarding: true)
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }
}

/// Settings & Data — stage preferences and local backups. No accounts, no microphone.
struct SettingsView: View {
    @StateObject private var model: SettingsViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var container: AppContainer
    @State private var showImporter = false
    @State private var showDelete = false
    @State private var confirmReplace = false

    init(container: AppContainer) {
        _model = StateObject(wrappedValue: SettingsViewModel(container: container))
    }

    var body: some View {
        ScreenScaffold(title: "Settings & Data", subtitle: "Everything stays on this device", backAction: { router.pop() }) {
            stageSection
            dataSection
            aboutSection
        }
        .alert($model.alert)
        .sheet(item: $model.share) { item in
            ShareSheet(items: item.urls)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            model.inspectImport(result: result)
        }
        .sheet(isPresented: $model.showImportPreview) {
            ImportPreviewSheet(
                inspection: model.inspection,
                canReplace: !model.liveRunExists,
                onCancel: { model.showImportPreview = false },
                onReplace: {
                    if model.replaceWithImport() { navigator.resetAll() }
                }
            )
        }
        .sheet(isPresented: $showDelete) {
            DeleteAllSheet(onCancel: { showDelete = false }) { typed in
                if model.deleteAll(confirmation: typed) {
                    showDelete = false
                    navigator.resetAll()
                }
            }
        }
    }

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Stage")
            CueCard {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(label: "Stage Text Size")
                    Picker("Stage Text Size", selection: settingBinding(\.stageTextSize)) {
                        ForEach(StageTextSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle(isOn: settingBinding(\.keepScreenAwake)) {
                    toggleLabel("Keep Screen Awake", "Only while a run is on screen in the foreground. Released as soon as you leave the stage.")
                }
                .tint(Palette.midnight)
                Toggle(isOn: settingBinding(\.reduceMotion)) {
                    toggleLabel("Reduce Motion", "Screens appear without sliding. The system setting is respected too.")
                }
                .tint(Palette.midnight)
                Button {
                    navigator.sheet = .stagePreview(versionID: container.performances.currentPerformance()
                        .flatMap { container.scripts.currentPublished(performanceID: $0.id)?.id })
                } label: {
                    Label("Preview Stage", systemImage: "eye")
                }
                .buttonStyle(.cueSecondary)
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Data")
            CueCard {
                Button {
                    router.push(.library(showArchived: true))
                } label: {
                    HStack {
                        Label("Archived Performances", systemImage: "archivebox")
                            .font(Typo.body)
                            .foregroundColor(Palette.ink)
                        Spacer()
                        Text("\(model.archivedCount)")
                            .font(Typo.monoHeadline)
                            .foregroundColor(Palette.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Palette.muted)
                    }
                    .frame(minHeight: Metrics.minTap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(model.totals.performances) performance(s) · \(model.totals.runs) run(s) · \(model.totals.markers) marker(s)")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)

                Button {
                    model.exportBackup()
                } label: {
                    Label("Export JSON Backup", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.cueSecondary)

                Button {
                    showImporter = true
                } label: {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.cueSecondary)
                .disabled(model.liveRunExists)
                Text(model.liveRunExists
                     ? "Import is unavailable while a run is unfinished. End or discard it first."
                     : "Import checks the file, shows what's inside and saves a safety copy of your current data before replacing anything.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CueCard(accent: Palette.stageRed) {
                Text("Delete All Data")
                    .font(Typo.headline)
                    .foregroundColor(Palette.redInk)
                Text("Removes every performance, version, run and marker from this device and resets preferences. Export a backup first if you might need it.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showDelete = true
                } label: {
                    Label("Delete All Data…", systemImage: "trash")
                }
                .buttonStyle(.cueDestructive)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "About")
            CueCard {
                Label("Works fully offline. No account, no server.", systemImage: "iphone")
                Label("No microphone, no recording, no speech analysis.", systemImage: "mic.slash")
                Label("No automatic scores — timing and your own notes only.", systemImage: "checkmark.seal")
                Button {
                    container.updateSettings { $0.hasCompletedOnboarding = false }
                } label: {
                    Label("Replay Onboarding", systemImage: "play.rectangle")
                }
                .buttonStyle(.cueSecondary)
            }
            .font(Typo.callout)
            .foregroundColor(Palette.ink)
        }
    }

    private func toggleLabel(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Palette.ink)
            Text(caption)
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { container.settings[keyPath: keyPath] },
            set: { value in container.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct ImportPreviewSheet: View {
    let inspection: BackupInspection?
    let canReplace: Bool
    let onCancel: () -> Void
    let onReplace: () -> Void
    @State private var confirm = false

    var body: some View {
        SheetScaffold(title: "Import Preview", closeTitle: "Cancel", onClose: onCancel) {
            if let inspection {
                if let preview = inspection.preview {
                    CueCard {
                        InfoRow(label: "Exported", value: DateText.short(preview.exportedAt))
                        InfoRow(label: "Active performances", value: "\(preview.performances)", monospaced: true)
                        InfoRow(label: "Archived performances", value: "\(preview.archivedPerformances)", monospaced: true)
                        InfoRow(label: "Versions", value: "\(preview.versions)", monospaced: true)
                        InfoRow(label: "Runs", value: "\(preview.runs)", monospaced: true)
                        InfoRow(label: "Markers", value: "\(preview.markers)", monospaced: true)
                        if preview.hasUnfinishedRun {
                            Text("Contains an unfinished run; it will be restored paused and marked as interrupted.")
                                .font(Typo.caption)
                                .foregroundColor(Palette.muted)
                        }
                    }
                }
                if inspection.isValid {
                    NoticeBanner(text: "All links between performances, versions, segments, runs and markers check out.", systemImage: "checkmark.seal.fill")
                    NoticeBanner(text: "Replace swaps ALL current data for this backup. A safety copy of your current data is saved first.",
                                 systemImage: "exclamationmark.triangle.fill", tone: .warning)
                    Button("Replace Current Data") { confirm = true }
                        .buttonStyle(.cuePrimary)
                        .disabled(!canReplace)
                    if !canReplace {
                        Text("Unavailable while a run is unfinished.")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Can't import this file")
                        ForEach(inspection.problems.prefix(12), id: \.self) { problem in
                            FieldError(text: problem)
                        }
                        Text("Your data was not changed.")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
            }
        }
        .confirmationDialog("Replace all data with this backup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Save Safety Copy & Replace", role: .destructive, action: onReplace)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct DeleteAllSheet: View {
    let onCancel: () -> Void
    let onDelete: (String) -> Void
    @State private var typed = ""

    var body: some View {
        SheetScaffold(title: "Delete All Data", closeTitle: "Cancel", onClose: onCancel) {
            NoticeBanner(text: "This permanently removes every performance, version, run, marker and reflection from this device. It can't be undone.",
                         systemImage: "exclamationmark.octagon.fill", tone: .warning)
            CueTextField(label: "Type DELETE to confirm", text: $typed, placeholder: "DELETE", capitalization: .characters)
            Button {
                onDelete(typed)
            } label: {
                Label("Delete Everything", systemImage: "trash.fill")
            }
            .buttonStyle(.cueDestructive)
            .disabled(typed != "DELETE")
        }
    }
}
