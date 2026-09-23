import Combine
import SwiftUI

@MainActor
final class RunsViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let run: RehearsalRun
        let markerCount: Int
        let plannedIncluded: Int
        var id: UUID { run.id }
    }

    @Published var filter: RunsFilter { didSet { reload() } }
    @Published private(set) var rows: [Row] = []
    @Published private(set) var liveRow: Row?
    @Published private(set) var performances: [Performance] = []
    @Published private(set) var versions: [ScriptVersion] = []

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, filter: RunsFilter) {
        self.container = container
        self.filter = filter
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        let db = container.store.database
        let withRuns = Set(db.runs.map(\.performanceID))
        performances = db.performances.filter { withRuns.contains($0.id) }.sorted { $0.name < $1.name }
        if let performanceID = filter.performanceID {
            versions = container.scripts.publishedVersions(performanceID: performanceID)
        } else {
            versions = []
        }
        let markerCounts = Dictionary(grouping: db.markers, by: \.runID).mapValues(\.count)
        func row(_ run: RehearsalRun) -> Row {
            Row(run: run, markerCount: markerCounts[run.id] ?? 0,
                plannedIncluded: run.includedIndices.reduce(0) { $0 + run.snapshot.segments[$1].plannedSeconds })
        }
        rows = container.rehearsals.runs(performanceID: filter.performanceID, versionID: filter.versionID, mode: filter.mode).map(row)
        if let live = container.rehearsals.liveRun(), filter.performanceID == nil || live.performanceID == filter.performanceID {
            liveRow = row(live)
        } else {
            liveRow = nil
        }
    }

    var performanceTitle: String {
        filter.performanceID.flatMap { id in performances.first { $0.id == id }?.name } ?? "All performances"
    }

    var versionTitle: String {
        filter.versionID.flatMap { id in versions.first { $0.id == id }?.shortName } ?? "All versions"
    }

    var modeTitle: String { filter.mode?.title ?? "All modes" }
}

/// Runs — every finished rehearsal, filterable by performance, version and mode.
struct RunsView: View {
    @StateObject private var model: RunsViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var navigator: AppNavigator
    let isTabRoot: Bool

    init(container: AppContainer, filter: RunsFilter, isTabRoot: Bool) {
        _model = StateObject(wrappedValue: RunsViewModel(container: container, filter: filter))
        self.isTabRoot = isTabRoot
    }

    var body: some View {
        ScreenScaffold(title: "Runs", subtitle: "\(model.rows.count) finished run(s)", backAction: isTabRoot ? nil : { router.pop() }) {
            HeaderIconButton(systemName: "rectangle.split.2x1", label: "Compare runs") {
                router.push(.compare(ComparePreset(performanceID: model.filter.performanceID)))
            }
        } content: {
            filters
            if let live = model.liveRow {
                SectionTitle(title: "In progress")
                Button {
                    navigator.presentStage(runID: live.run.id)
                } label: {
                    RunRow(row: live)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Stage Mode to continue")
            }
            if model.rows.isEmpty {
                EmptyStateView(asset: ArtAsset.notebook, size: CGSize(width: 88, height: 76),
                               title: model.filter == .all ? "No runs yet" : "No runs match",
                               message: model.filter == .all
                                   ? "Finish a rehearsal and it appears here with planned vs actual time for every segment."
                                   : "Try another performance, version or mode.")
            } else {
                SectionTitle(title: "Finished")
                LazyVStack(spacing: 10) {
                    ForEach(model.rows) { row in
                        Button {
                            router.push(.review(runID: row.run.id))
                        } label: {
                            RunRow(row: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterMenu(title: model.performanceTitle, systemImage: "theatermasks", active: model.filter.performanceID != nil) {
                    Button("All performances") { model.filter = RunsFilter(mode: model.filter.mode) }
                    ForEach(model.performances) { performance in
                        Button(performance.name) { model.filter = RunsFilter(performanceID: performance.id, mode: model.filter.mode) }
                    }
                }
                if model.filter.performanceID != nil {
                    filterMenu(title: model.versionTitle, systemImage: "square.stack.3d.up", active: model.filter.versionID != nil) {
                        Button("All versions") { model.filter.versionID = nil }
                        ForEach(model.versions) { version in
                            Button(version.displayName) { model.filter.versionID = version.id }
                        }
                    }
                }
                filterMenu(title: model.modeTitle, systemImage: "hand.tap", active: model.filter.mode != nil) {
                    Button("All modes") { model.filter.mode = nil }
                    ForEach(RunMode.allCases) { mode in
                        Button(mode.title) { model.filter.mode = mode }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterMenu<Items: View>(title: String, systemImage: String, active: Bool, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(active ? Palette.ink : Palette.blueInk)
            .padding(.horizontal, 12)
            .frame(minHeight: Metrics.minTap)
            .background(Capsule().fill(active ? Palette.spotlight : Palette.blueInk.opacity(0.08)))
        }
    }
}

struct RunRow: View {
    let row: RunsViewModel.Row

    var body: some View {
        let run = row.run
        return CueCard(accent: run.isLive ? Palette.spotlight : Palette.midnight, padding: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.snapshot.performanceName)
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text("\(DateText.short(run.startedAt)) · \(run.snapshot.versionDisplayName)")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Palette.muted)
            }
            HStack(spacing: 6) {
                StatusBadge.outcome(run.outcome)
                StatusBadge(run.mode.shortTitle, systemImage: run.mode.symbol)
                if run.isPartial && !run.isLive { StatusBadge.partial }
                if row.markerCount > 0 {
                    StatusBadge("\(row.markerCount)", systemImage: "bookmark.fill", style: .red)
                }
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE").font(Typo.eyebrow).foregroundColor(Palette.muted)
                    Text(TimeFormat.clock(run.totalActiveSeconds)).font(Typo.monoHeadline).foregroundColor(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLANNED").font(Typo.eyebrow).foregroundColor(Palette.muted)
                    Text(TimeFormat.clock(row.plannedIncluded)).font(Typo.monoHeadline).foregroundColor(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEGMENTS").font(Typo.eyebrow).foregroundColor(Palette.muted)
                    Text("\(run.completedCount)/\(run.includedIndices.count)").font(Typo.monoHeadline).foregroundColor(Palette.ink)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
