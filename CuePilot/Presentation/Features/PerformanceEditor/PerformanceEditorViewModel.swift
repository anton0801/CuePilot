import Combine
import Foundation

@MainActor
final class PerformanceEditorViewModel: ObservableObject {
    struct Form: Equatable {
        var name = ""
        var type: PerformanceType = .talk
        var hasTarget = false
        var targetSeconds = 10 * 60
        var versionLabel = ""
        var generalNote = ""

        var target: Int? { hasTarget ? targetSeconds : nil }
    }

    @Published var form = Form()
    @Published private(set) var savedForm = Form()
    @Published private(set) var performanceID: UUID?
    @Published private(set) var draft: ScriptVersion?
    @Published private(set) var currentPublished: ScriptVersion?
    @Published private(set) var liveRunExists = false
    @Published private(set) var didSaveOnce = false
    @Published private(set) var hasManualRuns = false
    @Published var alert: AlertMessage?
    @Published var nameError: String?

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, performanceID: UUID?) {
        self.container = container
        self.performanceID = performanceID
        loadForm()
        container.databaseChanges
            .sink { [weak self] _ in self?.reloadScript() }
            .store(in: &cancellables)
        if let performanceID { container.performances.touch(id: performanceID) }
    }

    // MARK: Derived state

    var isNew: Bool { performanceID == nil }
    var isDirty: Bool { form != savedForm }

    /// Draft if open, otherwise the published version being shown read-only.
    var workingVersion: ScriptVersion? { draft ?? currentPublished }
    var segments: [Segment] { workingVersion?.segments ?? [] }
    var plannedTotal: Int { segments.reduce(0) { $0 + $1.plannedSeconds } }
    var canRehearse: Bool { currentPublished != nil }
    var canPublish: Bool { draft != nil }
    var publishIssues: [ValidationIssue] {
        guard let performanceID else { return [] }
        return container.scripts.publishIssues(performanceID: performanceID)
    }

    var nextVersionNumber: Int {
        guard let performanceID else { return 1 }
        return container.scripts.nextVersionNumber(performanceID: performanceID)
    }

    /// Target is a personal goal: the gap is shown, never auto-corrected.
    var targetGap: Int? {
        guard let target = form.target, !segments.isEmpty else { return nil }
        return plannedTotal - target
    }

    var versionStatusText: String {
        if let draft {
            let base = draft.basedOnVersionID.flatMap { id in container.scripts.version(id: id) }
            return "Draft v\(draft.number)" + (base.map { " · based on \($0.shortName)" } ?? "")
        }
        if let published = currentPublished {
            return "\(published.shortName) · Published"
        }
        return "New draft"
    }

    // MARK: Loading

    private func loadForm() {
        guard let performanceID, let performance = container.performances.performance(id: performanceID) else {
            savedForm = form
            return
        }
        var loaded = Form()
        loaded.name = performance.name
        loaded.type = performance.type
        loaded.hasTarget = performance.targetTotalSeconds != nil
        loaded.targetSeconds = performance.targetTotalSeconds ?? 10 * 60
        let working = container.scripts.workingVersion(performanceID: performanceID)
        loaded.versionLabel = container.scripts.draft(performanceID: performanceID)?.label ?? ""
        loaded.generalNote = working?.generalNote ?? ""
        form = loaded
        savedForm = loaded
        reloadScript()
    }

    private func reloadScript() {
        guard let performanceID else { return }
        draft = container.scripts.draft(performanceID: performanceID)
        currentPublished = container.scripts.currentPublished(performanceID: performanceID)
        liveRunExists = container.rehearsals.liveRun() != nil
        hasManualRuns = container.insights.manualRunCount(performanceID: performanceID) > 0
    }

    // MARK: Commands

    /// Saves performance details and draft fields. Returns false when validation fails.
    @discardableResult
    func saveDraft() -> Bool {
        nameError = ValidationRules.performanceName(form.name)?.message
        if nameError != nil { return false }
        if let issue = ValidationRules.targetTotal(form.target) {
            alert = AlertMessage(title: "Check the target", message: issue.message)
            return false
        }
        do {
            if let performanceID {
                try container.performances.updateDetails(id: performanceID, name: form.name, type: form.type, targetTotalSeconds: form.target)
                let draftChanged = form.versionLabel.trimmed != savedForm.versionLabel.trimmed || form.generalNote != savedForm.generalNote
                // Label and note belong to the script: changing them on a published version opens a new draft.
                if draftChanged {
                    try container.scripts.updateDraftDetails(performanceID: performanceID, label: form.versionLabel, generalNote: form.generalNote)
                }
            } else {
                let created = try container.performances.create(
                    name: form.name, type: form.type, targetTotalSeconds: form.target,
                    versionLabel: form.versionLabel, generalNote: form.generalNote
                )
                performanceID = created.id
            }
            form.name = form.name.trimmed
            form.versionLabel = form.versionLabel.trimmed
            savedForm = form
            didSaveOnce = true
            reloadScript()
            Haptics.success()
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }

    func discardChanges() {
        form = savedForm
        nameError = nil
    }

    /// A new performance must exist (valid name) before segments can be added to it.
    func ensureSaved() -> UUID? {
        if let performanceID, !isDirty { return performanceID }
        return saveDraft() ? performanceID : nil
    }

    func publish(changeNote: String) -> ScriptVersion? {
        guard let performanceID else { return nil }
        if isDirty && !saveDraft() { return nil }
        do {
            let version = try container.scripts.publishDraft(performanceID: performanceID, changeNote: changeNote)
            Haptics.success()
            return version
        } catch {
            alert = AlertMessage(error)
            return nil
        }
    }

    func reorder(to ids: [UUID]) {
        guard let performanceID else { return }
        do {
            try container.scripts.reorderSegments(performanceID: performanceID, orderedIDs: ids)
        } catch {
            alert = AlertMessage(error)
        }
    }
}
