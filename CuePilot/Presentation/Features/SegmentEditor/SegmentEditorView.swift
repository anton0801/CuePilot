import Combine
import SwiftUI

@MainActor
final class SegmentEditorViewModel: ObservableObject {
    @Published var segment: Segment
    @Published private(set) var original: Segment?
    @Published private(set) var draftExists: Bool
    @Published private(set) var publishedName: String?
    @Published private(set) var position: Int?
    @Published var issues: [ValidationIssue] = []
    @Published var alert: AlertMessage?

    let performanceID: UUID
    private let container: AppContainer

    init(container: AppContainer, performanceID: UUID, segmentID: UUID?) {
        self.container = container
        self.performanceID = performanceID
        let working = container.scripts.workingVersion(performanceID: performanceID)
        if let segmentID, let existing = working?.segment(withID: segmentID) {
            segment = existing
            original = existing
            position = working?.segments.firstIndex(of: existing).map { $0 + 1 }
        } else {
            segment = .blank()
            original = nil
            position = nil
        }
        draftExists = container.scripts.draft(performanceID: performanceID) != nil
        publishedName = container.scripts.currentPublished(performanceID: performanceID)?.shortName
    }

    var isNew: Bool { original == nil }
    var nextVersionNumber: Int { container.scripts.nextVersionNumber(performanceID: performanceID) }

    func error(containing word: String) -> String? {
        issues.first { $0.message.localizedCaseInsensitiveContains(word) }?.message
    }

    @discardableResult
    func save() -> Bool {
        issues = ValidationRules.segment(segment)
        guard issues.isEmpty else {
            Haptics.warning()
            return false
        }
        do {
            try container.scripts.saveSegment(segment, performanceID: performanceID)
            segment.title = segment.title.trimmed
            original = segment
            Haptics.success()
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }

    func duplicate() -> Segment? {
        if segment != original, !save() { return nil }
        do {
            return try container.scripts.duplicateSegment(id: segment.id, performanceID: performanceID)
        } catch {
            alert = AlertMessage(error)
            return nil
        }
    }

    func delete() -> Bool {
        do {
            try container.scripts.deleteSegment(id: segment.id, performanceID: performanceID)
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }
}

/// Segment Editor — title, planned time, cue and notes for one part of the performance.
struct SegmentEditorView: View {
    @StateObject private var model: SegmentEditorViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var container: AppContainer
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @State private var showPreview = false

    init(container: AppContainer, performanceID: UUID, segmentID: UUID?) {
        _model = StateObject(wrappedValue: SegmentEditorViewModel(container: container, performanceID: performanceID, segmentID: segmentID))
    }

    private var hasChanges: Bool {
        model.isNew ? !model.segment.title.trimmed.isEmpty || !model.segment.cueText.isEmpty || !model.segment.detailedNotes.isEmpty : model.segment != model.original
    }

    var body: some View {
        ScreenScaffold(
            title: model.isNew ? "New Segment" : "Edit Segment",
            subtitle: model.position.map { "Segment \($0)" } ?? "Added to the end",
            backAction: back
        ) {
            HeaderIconButton(systemName: "eye", label: "Preview cue") { showPreview = true }
        } content: {
            HStack(alignment: .center, spacing: 14) {
                Illustration(ArtAsset.spotlight, size: CGSize(width: 64, height: 80))
                VStack(alignment: .leading, spacing: 4) {
                    Text("One clear part")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text("The cue is what you'll see on stage — keep it to a few words you can read at a glance.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.draftExists, let published = model.publishedName {
                NoticeBanner(text: "Saving creates Draft v\(model.nextVersionNumber). \(published) and its runs stay unchanged.", systemImage: "lock.fill")
            }

            CueCard {
                CueTextField(label: "Title", text: $model.segment.title, placeholder: "e.g. Opening story",
                             required: true, limit: Limits.segmentTitleMax, error: model.error(containing: "Title"))
                DurationEditor(label: "Planned Duration", seconds: $model.segment.plannedSeconds, range: Limits.plannedSeconds,
                               steps: [10, 60], presets: [30, 60, 90, 120, 180, 300, 600], required: true)
                if let error = model.error(containing: "Planned") { FieldError(text: error) }
            }

            CueCard {
                CueTextEditor(label: "Cue Text", text: $model.segment.cueText,
                              placeholder: "Shown big on stage. e.g. “Start with the broken umbrella.”",
                              limit: Limits.cueTextMax, minHeight: 90, error: model.error(containing: "Cue"))
                CueTextEditor(label: "Detailed Notes", text: $model.segment.detailedNotes,
                              placeholder: "Private notes for preparation. Not shown on stage; excluded from exports unless you choose to include them.",
                              limit: Limits.detailedNotesMax, minHeight: 120, error: model.error(containing: "notes"))
                Toggle(isOn: $model.segment.isOptional) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Optional Segment")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Palette.ink)
                        Text("Can be skipped during a run. It stays in the plan, marked Optional.")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
                .tint(Palette.midnight)
            }

            Button {
                if model.save() { router.pop() }
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.cuePrimary)

            HStack(spacing: 10) {
                Button {
                    showPreview = true
                } label: {
                    Label("Preview Cue", systemImage: "eye")
                }
                .buttonStyle(.cueSecondary)
                if !model.isNew {
                    Button {
                        if let copy = model.duplicate() {
                            router.replaceTop(with: .segmentEditor(performanceID: model.performanceID, segmentID: copy.id))
                        }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.cueSecondary)
                }
            }
            if !model.isNew {
                Button {
                    confirmDelete = true
                } label: {
                    Label("Delete Segment", systemImage: "trash")
                }
                .buttonStyle(.cueDestructive)
                Text("Deleting removes it from the draft only. Published versions and past runs keep it.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
        }
        .popGestureBlocked(hasChanges)
        .alert($model.alert)
        .confirmationDialog("Delete “\(model.segment.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from Draft", role: .destructive) {
                if model.delete() { router.pop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past runs and published versions are not affected.")
        }
        .confirmationDialog("Save this segment?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Save") { if model.save() { router.pop() } }
            Button("Discard Changes", role: .destructive) { router.pop() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $showPreview) {
            CuePreviewSheet(segment: model.segment, stageScale: container.settings.stageTextSize.scale) { showPreview = false }
        }
    }

    private func back() {
        if hasChanges { confirmLeave = true } else { router.pop() }
    }
}

/// How the cue will read in Stage Mode. Static — the clock is not running.
struct CuePreviewSheet: View {
    let segment: Segment
    let stageScale: Double
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.midnight.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("PREVIEW · CLOCK NOT RUNNING")
                    .font(Typo.eyebrow)
                    .tracking(1.4)
                    .foregroundColor(Palette.spotlight)
                Text(segment.title.isEmpty ? "Untitled segment" : segment.title)
                    .font(Typo.display(28 * stageScale))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if segment.isOptional {
                    StatusBadge("Optional", systemImage: "circle.dashed", style: .onBlue)
                }
                Text(segment.cueText.trimmed.isEmpty ? "No cue text yet." : segment.cueText)
                    .font(.system(size: 22 * stageScale, weight: .medium, design: .rounded))
                    .foregroundColor(segment.cueText.trimmed.isEmpty ? Palette.onBlueMuted : .white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
                Spacer()
                HStack(alignment: .firstTextBaseline) {
                    Text("0:00")
                        .font(Typo.timer(72 * min(stageScale, 1.2)))
                        .foregroundColor(Palette.spotlight)
                    Text("of \(TimeFormat.clock(segment.plannedSeconds)) planned")
                        .font(Typo.monoHeadline)
                        .foregroundColor(Palette.onBlueMuted)
                }
            }
            .padding(24)
            .padding(.top, 30)
            .readableWidth()
            Button("Close", action: onClose)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Palette.spotlight)
                .frame(minWidth: Metrics.minTap, minHeight: Metrics.minTap)
                .padding(12)
        }
    }
}
