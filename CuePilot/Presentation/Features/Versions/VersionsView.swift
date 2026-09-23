import Combine
import SwiftUI

@MainActor
final class VersionsViewModel: ObservableObject {
    @Published private(set) var items: [VersionListItem] = []
    @Published private(set) var performance: Performance?
    @Published var alert: AlertMessage?

    let performanceID: UUID
    let highlight: UUID?
    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, performanceID: UUID, highlight: UUID?) {
        self.container = container
        self.performanceID = performanceID
        self.highlight = highlight
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    var draft: ScriptVersion? { items.first { $0.version.isDraft }?.version }
    var publishIssues: [ValidationIssue] { container.scripts.publishIssues(performanceID: performanceID) }

    func reload() {
        performance = container.performances.performance(id: performanceID)
        items = container.scripts.versionItems(performanceID: performanceID)
    }

    func version(_ id: UUID) -> ScriptVersion? { container.scripts.version(id: id) }

    func publish(changeNote: String) -> Bool {
        perform { try container.scripts.publishDraft(performanceID: performanceID, changeNote: changeNote) }
    }

    func createDraft(from versionID: UUID, replacing: Bool) -> Bool {
        perform { try container.scripts.createDraft(from: versionID, replacingDraft: replacing) }
    }

    func setCurrent(_ versionID: UUID) {
        _ = perform { try container.scripts.setCurrent(versionID: versionID) }
    }

    func discardDraft() {
        _ = perform { try container.scripts.discardDraft(performanceID: performanceID) }
    }

    @discardableResult
    private func perform(_ action: () throws -> Any) -> Bool {
        do {
            _ = try action()
            Haptics.success()
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }
}

/// Script Versions — keeps every result tied to the script that was actually used.
struct VersionsView: View {
    @StateObject private var model: VersionsViewModel
    @EnvironmentObject private var router: Router
    @State private var viewing: ScriptVersion?
    @State private var showPublish = false
    @State private var replaceDraftFrom: ScriptVersion?
    @State private var confirmDiscard = false

    init(container: AppContainer, performanceID: UUID, highlight: UUID?) {
        _model = StateObject(wrappedValue: VersionsViewModel(container: container, performanceID: performanceID, highlight: highlight))
    }

    var body: some View {
        ScreenScaffold(title: "Script Versions", subtitle: model.performance?.name, backAction: { router.pop() }) {
            if model.items.isEmpty {
                EmptyStateView(asset: ArtAsset.scriptCards, size: CGSize(width: 64, height: 55),
                               title: "No versions", message: "Versions appear once the performance has a draft.")
            } else {
                NoticeBanner(text: "Published versions are locked. A version with runs can't be removed on its own — archive the whole performance instead.",
                             systemImage: "lock.fill")
                ForEach(model.items) { item in
                    VersionCard(
                        item: item,
                        highlighted: item.id == model.highlight,
                        basedOn: item.version.basedOnVersionID.flatMap(model.version)?.shortName,
                        hasDraft: model.draft != nil,
                        onView: { viewing = item.version },
                        onEditDraft: { router.show(.performanceEditor(model.performanceID)) },
                        onPublish: { showPublish = true },
                        onDiscard: { confirmDiscard = true },
                        onSetCurrent: { model.setCurrent(item.id) },
                        onCreateDraft: {
                            if model.draft != nil {
                                replaceDraftFrom = item.version
                            } else if model.createDraft(from: item.id, replacing: false) {
                                router.show(.performanceEditor(model.performanceID))
                            }
                        },
                        onRuns: { router.push(.runs(RunsFilter(performanceID: model.performanceID, versionID: item.id))) }
                    )
                }
            }
        }
        .alert($model.alert)
        .sheet(item: $viewing) { version in
            VersionDetailSheet(version: version) { viewing = nil }
        }
        .sheet(isPresented: $showPublish) {
            PublishDraftSheet(versionNumber: model.draft?.number ?? 0, issues: model.publishIssues, onCancel: { showPublish = false }) { note in
                if model.publish(changeNote: note) { showPublish = false }
            }
        }
        .confirmationDialog("Replace the open draft?", isPresented: replaceBinding, titleVisibility: .visible) {
            if let source = replaceDraftFrom {
                Button("Replace with copy of \(source.shortName)", role: .destructive) {
                    if model.createDraft(from: source.id, replacing: true) {
                        router.show(.performanceEditor(model.performanceID))
                    }
                    replaceDraftFrom = nil
                }
            }
            Button("Keep Current Draft", role: .cancel) { replaceDraftFrom = nil }
        } message: {
            Text("Only one draft exists at a time. Unpublished changes in the current draft will be lost.")
        }
        .confirmationDialog("Discard the draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Unused Draft", role: .destructive) { model.discardDraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Drafts have no runs. Published versions stay as they are.")
        }
    }

    private var replaceBinding: Binding<Bool> {
        Binding(get: { replaceDraftFrom != nil }, set: { if !$0 { replaceDraftFrom = nil } })
    }
}

private struct VersionCard: View {
    let item: VersionListItem
    let highlighted: Bool
    let basedOn: String?
    let hasDraft: Bool
    let onView: () -> Void
    let onEditDraft: () -> Void
    let onPublish: () -> Void
    let onDiscard: () -> Void
    let onSetCurrent: () -> Void
    let onCreateDraft: () -> Void
    let onRuns: () -> Void

    var body: some View {
        let version = item.version
        CueCard(accent: version.isDraft ? Palette.spotlight : (item.isCurrent ? Palette.stageRed : Palette.midnight)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.displayName)
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text(dateLine)
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
                HStack(spacing: 4) {
                    if version.isDraft { StatusBadge.draft } else { StatusBadge.published }
                    if item.isCurrent { StatusBadge.current }
                }
            }
            if highlighted {
                StatusBadge("Used by the run you came from", systemImage: "arrow.turn.down.right", style: .yellow)
            }
            HStack(spacing: 8) {
                StatTile(label: "Segments", value: "\(version.segments.count)")
                StatTile(label: "Planned", value: TimeFormat.clock(version.plannedTotalSeconds))
                StatTile(label: "Linked Runs", value: "\(item.linkedRunCount)")
            }
            if !version.changeNote.trimmed.isEmpty {
                Text("“\(version.changeNote)”")
                    .font(Typo.callout.italic())
                    .foregroundColor(Palette.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(title: "View Version", systemImage: "eye", action: onView)
                    if version.isDraft {
                        ChipButton(title: "Edit Draft", systemImage: "square.and.pencil", action: onEditDraft)
                        ChipButton(title: "Publish Draft", systemImage: "lock.fill", action: onPublish)
                        ChipButton(title: "Discard Unused Draft", systemImage: "trash", tint: Palette.redInk, action: onDiscard)
                    } else {
                        ChipButton(title: "Create Draft from Version", systemImage: "doc.on.doc", action: onCreateDraft)
                        if !item.isCurrent {
                            ChipButton(title: "Set Current", systemImage: "star", action: onSetCurrent)
                        }
                        if item.linkedRunCount > 0 {
                            ChipButton(title: "Runs", systemImage: "list.bullet.rectangle", action: onRuns)
                        }
                    }
                }
            }
            if !version.isDraft && item.isCurrent {
                Text("Current = the default in Rehearsal Setup. Past runs always keep their own version.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
        }
    }

    private var dateLine: String {
        let version = item.version
        var parts = ["Created \(DateText.short(version.createdAt))"]
        if let published = version.publishedAt { parts.append("Published \(DateText.day(published))") }
        if let basedOn { parts.append("from \(basedOn)") }
        return parts.joined(separator: " · ")
    }
}

private struct VersionDetailSheet: View {
    let version: ScriptVersion
    let onClose: () -> Void

    var body: some View {
        SheetScaffold(title: version.displayName, onClose: onClose) {
            HStack(spacing: 6) {
                if version.isDraft { StatusBadge.draft } else { StatusBadge.published }
                StatusBadge("\(version.segments.count) segments · \(TimeFormat.clock(version.plannedTotalSeconds))")
            }
            if !version.generalNote.trimmed.isEmpty {
                CueCard {
                    Text("General Note").font(Typo.headline).foregroundColor(Palette.ink)
                    Text(version.generalNote).font(Typo.body).foregroundColor(Palette.ink)
                }
            }
            if version.segments.isEmpty {
                Text("No segments.").font(Typo.callout).foregroundColor(Palette.muted)
            }
            ForEach(Array(version.segments.enumerated()), id: \.element.id) { index, segment in
                SegmentRow(position: index + 1, segment: segment)
            }
        }
    }
}
