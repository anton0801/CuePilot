import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var query = "" { didSet { reload() } }
    @Published var showArchived: Bool { didSet { reload() } }
    @Published private(set) var rows: [PerformanceSummary] = []
    @Published private(set) var activeCount = 0
    @Published private(set) var archivedCount = 0
    @Published var alert: AlertMessage?
    /// Performance waiting for a decision about its unfinished run before archiving.
    @Published var archiveCandidate: PerformanceSummary?

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, showArchived: Bool) {
        self.container = container
        self.showArchived = showArchived
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        let useCases = container.performances
        // Each row is computed from its own performance only — search never mixes results of different scripts.
        rows = useCases.performances(archived: showArchived, matching: query).map(useCases.summary(for:))
        activeCount = useCases.performances(archived: false).count
        archivedCount = useCases.performances(archived: true).count
    }

    @discardableResult
    func duplicate(_ summary: PerformanceSummary) -> Performance? {
        do {
            return try container.performances.duplicateStructure(id: summary.performance.id)
        } catch {
            alert = AlertMessage(error)
            return nil
        }
    }

    func archive(_ summary: PerformanceSummary) {
        if summary.liveRun != nil {
            archiveCandidate = summary
            return
        }
        perform { try container.performances.archive(id: summary.performance.id) }
    }

    func archive(_ summary: PerformanceSummary, resolving resolution: LiveRunResolution) {
        perform { try container.performances.archive(id: summary.performance.id, resolvingLiveRun: resolution) }
        archiveCandidate = nil
    }

    func restore(_ summary: PerformanceSummary) {
        perform { try container.performances.restore(id: summary.performance.id) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { alert = AlertMessage(error) }
    }
}

/// Performance Library — search, active/archived, duplicate structure, archive and restore.
struct LibraryView: View {
    @StateObject private var model: LibraryViewModel
    @EnvironmentObject private var router: Router
    @State private var showArchiveDialog = false

    init(container: AppContainer, showArchived: Bool) {
        _model = StateObject(wrappedValue: LibraryViewModel(container: container, showArchived: showArchived))
    }

    var body: some View {
        ScreenScaffold(title: "Library", subtitle: "\(model.activeCount) active · \(model.archivedCount) archived", backAction: { router.pop() }) {
            HeaderIconButton(systemName: "plus", label: "Create performance", filled: true) {
                router.push(.performanceEditor(nil))
            }
        } content: {
            searchField
            Picker("Show", selection: $model.showArchived) {
                Text("Active").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(.segmented)

            if model.rows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.rows) { row in
                        LibraryRow(
                            summary: row,
                            onOpen: { router.push(.performanceEditor(row.performance.id)) },
                            onDuplicate: {
                                if let copy = model.duplicate(row) { router.push(.performanceEditor(copy.id)) }
                            },
                            onArchive: { model.archive(row) },
                            onRestore: { model.restore(row) },
                            onRuns: { router.push(.runs(RunsFilter(performanceID: row.performance.id))) }
                        )
                    }
                }
            }
        }
        .alert($model.alert)
        .onChange(of: model.archiveCandidate?.id) { showArchiveDialog = $0 != nil }
        .confirmationDialog("This performance has an unfinished run", isPresented: $showArchiveDialog, titleVisibility: .visible) {
            if let candidate = model.archiveCandidate {
                Button("End Run Early & Archive") { model.archive(candidate, resolving: .endEarly) }
                Button("Discard Run & Archive", role: .destructive) { model.archive(candidate, resolving: .discard) }
            }
            Button("Cancel", role: .cancel) { model.archiveCandidate = nil }
        } message: {
            Text("Archiving keeps all history. Finish the run first: end it early (completed segments stay) or discard it.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Palette.muted)
            TextField("Search performances", text: $model.query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Palette.muted)
                }
                .frame(width: Metrics.minTap, height: Metrics.minTap)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1.5))
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.query.trimmed.isEmpty {
            EmptyStateView(asset: ArtAsset.scriptCards, size: CGSize(width: 112, height: 96),
                           title: "No matches", message: "Nothing matches “\(model.query.trimmed)” in \(model.showArchived ? "archived" : "active") performances.")
        } else if model.showArchived {
            EmptyStateView(asset: ArtAsset.scriptCards, size: CGSize(width: 112, height: 96),
                           title: "Nothing archived", message: "Archived performances keep their versions, runs and markers. Restore them any time.")
        } else {
            EmptyStateView(asset: ArtAsset.scriptCards, size: CGSize(width: 112, height: 96),
                           title: "No performances yet",
                           message: "Create a performance and split it into segments with a planned time and a short cue.",
                           actionTitle: "Create Performance") { router.push(.performanceEditor(nil)) }
        }
    }
}

private struct LibraryRow: View {
    let summary: PerformanceSummary
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onRuns: () -> Void

    var body: some View {
        CueCard(accent: summary.performance.isArchived ? Palette.muted : Palette.stageRed, padding: 14) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.performance.name)
                            .font(Typo.headline)
                            .foregroundColor(Palette.ink)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            StatusBadge(summary.performance.type.title, systemImage: summary.performance.type.symbol)
                            if let version = summary.currentVersion {
                                StatusBadge(version.shortName, systemImage: "lock.fill", style: .blue)
                            }
                            if summary.draft != nil {
                                StatusBadge.draft
                            }
                            if summary.liveRun != nil {
                                StatusBadge("Run open", systemImage: "pause.fill", style: .yellow)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(action: onOpen) { Label("Open", systemImage: "square.and.pencil") }
                    Button(action: onDuplicate) { Label("Duplicate Structure", systemImage: "plus.square.on.square") }
                    Button(action: onRuns) { Label("Open Runs", systemImage: "list.bullet.rectangle") }
                    if summary.performance.isArchived {
                        Button(action: onRestore) { Label("Restore", systemImage: "arrow.uturn.left") }
                    } else {
                        Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Palette.blueInk)
                        .frame(width: Metrics.minTap, height: Metrics.minTap)
                }
                .accessibilityLabel("Actions for \(summary.performance.name)")
            }
            HStack(spacing: 8) {
                metric("Segments", "\(summary.segmentCount)")
                metric("Planned", summary.plannedTotalSeconds.map(TimeFormat.clock) ?? "Not Set Up")
                metric("Last Rehearsed", summary.lastRun.map { DateText.day($0.startedAt) } ?? "Never")
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Typo.eyebrow)
                .foregroundColor(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Typo.monoCaption.weight(.semibold))
                .foregroundColor(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
