import Combine
import SwiftUI

@MainActor
final class CompareRunsViewModel: ObservableObject {
    enum Slot: String, Identifiable {
        case a, b
        var id: String { rawValue }
        var title: String { self == .a ? "Run A" : "Run B" }
    }

    @Published var performanceID: UUID? { didSet { if oldValue != performanceID { pickDefaults() } } }
    @Published var runAID: UUID? { didSet { rebuild() } }
    @Published var runBID: UUID? { didSet { rebuild() } }
    @Published var showMarkers = false
    @Published private(set) var comparison: RunComparison?
    @Published private(set) var eligibility: RunComparison.Eligibility?
    @Published private(set) var candidates: [RehearsalRun] = []
    @Published private(set) var performances: [Performance] = []
    @Published var alert: AlertMessage?

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, preset: ComparePreset) {
        self.container = container
        let presetRun = (preset.runB ?? preset.runA).flatMap { container.rehearsals.run(id: $0) }
        performanceID = preset.performanceID ?? presetRun?.performanceID ?? container.performances.currentPerformance()?.id
        loadCandidates()
        if preset.runA != nil || preset.runB != nil {
            runAID = preset.runA
            runBID = preset.runB
        } else {
            pickDefaults()
        }
        rebuild()
        container.databaseChanges
            .dropFirst()
            .sink { [weak self] _ in
                self?.loadCandidates()
                self?.rebuild()
            }
            .store(in: &cancellables)
    }

    var runA: RehearsalRun? { candidates.first { $0.id == runAID } }
    var runB: RehearsalRun? { candidates.first { $0.id == runBID } }

    var performanceName: String {
        performances.first { $0.id == performanceID }?.name ?? "Choose a performance"
    }

    private func loadCandidates() {
        let db = container.store.database
        let withRuns = Set(db.runs.filter { !$0.isLive }.map(\.performanceID))
        performances = db.performances.filter { withRuns.contains($0.id) }.sorted { $0.name < $1.name }
        if performanceID == nil { performanceID = performances.first?.id }
        candidates = performanceID.map { container.rehearsals.runs(performanceID: $0) } ?? []
    }

    private func pickDefaults() {
        loadCandidates()
        let preferred = performanceID.flatMap { container.scripts.currentPublished(performanceID: $0)?.id }
        if let pair = RunComparison.defaultPair(from: candidates, preferredVersionID: preferred) {
            runAID = pair.a.id
            runBID = pair.b.id
        } else {
            runAID = candidates.dropFirst().first?.id
            runBID = candidates.first?.id
        }
    }

    private func rebuild() {
        guard let a = runA, let b = runB else {
            comparison = nil
            eligibility = nil
            return
        }
        let result = RunComparison.eligibility(a, b)
        eligibility = result
        if case .blocked = result {
            comparison = nil
            return
        }
        comparison = RunComparison.build(
            a: a, b: b,
            markersA: container.rehearsals.markers(runID: a.id),
            markersB: container.rehearsals.markers(runID: b.id)
        )
    }

    func select(_ run: RehearsalRun, for slot: Slot) {
        switch slot {
        case .a: runAID = run.id
        case .b: runBID = run.id
        }
    }

    /// Why a run can't fill a slot next to the other chosen run, if it can't.
    func blockReason(for run: RehearsalRun, slot: Slot) -> String? {
        guard let other = slot == .a ? runB : runA, other.id != run.id else { return nil }
        if case let .blocked(reason) = RunComparison.eligibility(run, other) { return reason }
        return nil
    }

    func swap() {
        let a = runAID
        runAID = runBID
        runBID = a
    }

    /// Open a matched segment in the draft (created from the current version if needed).
    func openInDraft(segmentID: UUID) -> Bool {
        guard let performanceID else { return false }
        do {
            let draft = try container.scripts.ensureDraft(performanceID: performanceID)
            guard draft.segment(withID: segmentID) != nil else {
                alert = AlertMessage(title: "Not in the draft",
                                     message: "This segment was removed from the current draft. Past runs still keep it in their snapshots.")
                return false
            }
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }
}

/// Compare Runs — where exactly did the timing change between two rehearsals?
struct CompareRunsView: View {
    @StateObject private var model: CompareRunsViewModel
    @EnvironmentObject private var router: Router
    @State private var picking: CompareRunsViewModel.Slot?

    init(container: AppContainer, preset: ComparePreset) {
        _model = StateObject(wrappedValue: CompareRunsViewModel(container: container, preset: preset))
    }

    var body: some View {
        ScreenScaffold(title: "Compare Runs", subtitle: model.performanceName, backAction: { router.pop() }) {
            if let comparison = model.comparison {
                HeaderIconButton(systemName: "square.and.arrow.up", label: "Export comparison") {
                    router.push(.export(ExportPreset(kind: .comparison, performanceID: model.performanceID,
                                                     runA: comparison.runA.id, runB: comparison.runB.id)))
                }
            }
        } content: {
            if model.performances.isEmpty {
                EmptyStateView(asset: ArtAsset.comparisonCards, size: CGSize(width: 72, height: 64),
                               title: "Nothing to compare yet",
                               message: "Finish two runs of the same performance — ideally two Manual Next runs of one version.")
            } else {
                pickers
                resultSection
            }
        }
        .alert($model.alert)
        .sheet(item: $picking) { slot in
            RunPickerSheet(model: model, slot: slot) { picking = nil }
        }
    }

    private var pickers: some View {
        CueCard {
            HStack(alignment: .top, spacing: 12) {
                Illustration(ArtAsset.comparisonCards, size: CGSize(width: 72, height: 64))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Segment by segment")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text("Difference is B − A, only where a segment was completed in both runs. No overall score.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.performances.count > 1 {
                Menu {
                    ForEach(model.performances) { performance in
                        Button(performance.name) { model.performanceID = performance.id }
                    }
                } label: {
                    Label(model.performanceName, systemImage: "theatermasks")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Palette.blueInk)
                        .frame(minHeight: Metrics.minTap)
                }
            }
            slotButton(.a, run: model.runA, color: Palette.stageRed)
            slotButton(.b, run: model.runB, color: Palette.spotlightDeep)
            HStack(spacing: 10) {
                ChipButton(title: "Choose Runs", systemImage: "list.bullet") { picking = .b }
                ChipButton(title: "Swap A/B", systemImage: "arrow.left.arrow.right") { model.swap() }
                Spacer()
            }
            if let id = model.performanceID {
                ChipButton(title: "Segment History · all runs", systemImage: "chart.bar.xaxis") {
                    router.push(.segmentHistory(performanceID: id))
                }
            }
            Toggle(isOn: $model.showMarkers) {
                Text("Show Markers")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Palette.ink)
            }
            .tint(Palette.midnight)
        }
    }

    private func slotButton(_ slot: CompareRunsViewModel.Slot, run: RehearsalRun?, color: Color) -> some View {
        Button {
            picking = slot
        } label: {
            HStack(spacing: 10) {
                Text(slot == .a ? "A" : "B")
                    .font(Typo.monoHeadline)
                    .foregroundColor(slot == .a ? .white : Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color))
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.map { DateText.short($0.startedAt) } ?? "Choose \(slot.title)")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    if let run {
                        Text("\(run.snapshot.versionDisplayName) · \(run.mode.title) · \(run.outcome?.title ?? "")")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.blueInk)
            }
            .padding(10)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.title): \(run.map { DateText.short($0.startedAt) } ?? "not chosen")")
    }

    @ViewBuilder
    private var resultSection: some View {
        switch model.eligibility {
        case nil:
            NoticeBanner(text: "Choose two finished runs of this performance.", systemImage: "rectangle.split.2x1")
        case let .blocked(reason):
            NoticeBanner(text: reason, systemImage: "nosign", tone: .warning)
        case .warningDifferentVersions, .ok:
            if let comparison = model.comparison {
                if model.eligibility == .warningDifferentVersions {
                    NoticeBanner(
                        text: "Different script versions (\(comparison.runA.snapshot.versionDisplayName) vs \(comparison.runB.snapshot.versionDisplayName)). Segments are matched by their stable ID, not position; edited ones are marked Changed.",
                        systemImage: "exclamationmark.triangle.fill", tone: .warning
                    )
                }
                totals(comparison)
                rows(comparison)
                unmatched(comparison)
            }
        }
    }

    private func totals(_ comparison: RunComparison) -> some View {
        CueCard(accent: Palette.stageRed) {
            if let total = comparison.totalDifference {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("B VS A")
                            .font(Typo.eyebrow)
                            .foregroundColor(Palette.muted)
                        Text(TimeFormat.delta(total))
                            .font(Typo.timer(34))
                            .foregroundColor(total > 0 ? Palette.redInk : Palette.ink)
                    }
                    Spacer()
                    DifferenceLabel(seconds: total)
                }
                Text("Across \(comparison.countedRows.count) segment(s) completed in both runs. Skipped, unfinished and not-reached segments are left out.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No segment was completed in both runs, so there's no difference to add up.")
                    .font(Typo.callout)
                    .foregroundColor(Palette.muted)
            }
            if let growth = comparison.biggestGrowth, let diff = growth.difference {
                NoticeBanner(text: "Biggest growth: “\(growth.title)” took \(TimeFormat.delta(diff)) more in B — a concrete place to trim.",
                             systemImage: "scissors", tone: .spotlight)
            }
        }
    }

    private func rows(_ comparison: RunComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Segment · A · B · Difference")
            ForEach(comparison.rows) { row in
                ComparisonRowView(row: row, maxValue: Double(comparison.maxActual), showMarkers: model.showMarkers) {
                    if model.openInDraft(segmentID: row.segmentID), let id = model.performanceID {
                        router.push(.segmentEditor(performanceID: id, segmentID: row.segmentID))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unmatched(_ comparison: RunComparison) -> some View {
        if !comparison.onlyInA.isEmpty || !comparison.onlyInB.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Unmatched segments")
                CueCard {
                    ForEach(comparison.onlyInA) { item in
                        unmatchedRow(label: "Only in A", item: item)
                    }
                    ForEach(comparison.onlyInB) { item in
                        unmatchedRow(label: "Only in B", item: item)
                    }
                    Text("Added or removed between versions — not part of the difference.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
        }
    }

    private func unmatchedRow(label: String, item: UnmatchedSegment) -> some View {
        HStack {
            StatusBadge(label, style: .neutral)
            Text(item.segment.title)
                .font(Typo.callout)
                .foregroundColor(Palette.ink)
            Spacer()
            Text(item.cell.actual.map(TimeFormat.clock) ?? item.cell.statusText)
                .font(Typo.monoCaption)
                .foregroundColor(Palette.muted)
        }
    }
}

/// "Longer / Shorter" with a symbol, never colour alone.
struct DifferenceLabel: View {
    let seconds: Int

    var body: some View {
        Label("\(word) \(TimeFormat.delta(seconds))", systemImage: symbol)
            .font(Typo.monoCaption.weight(.bold))
            .foregroundColor(seconds > 0 ? Palette.redInk : Palette.blueInk)
            .accessibilityLabel("\(word) by \(TimeFormat.spoken(abs(seconds)))")
    }

    private var word: String { seconds > 0 ? "Longer" : (seconds < 0 ? "Shorter" : "Same") }
    private var symbol: String { seconds > 0 ? "arrow.up.circle.fill" : (seconds < 0 ? "arrow.down.circle.fill" : "equal.circle.fill") }
}

private struct ComparisonRowView: View {
    let row: ComparisonRow
    let maxValue: Double
    let showMarkers: Bool
    let onOpenInDraft: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(Typo.headline)
                    .foregroundColor(Palette.ink)
                if row.isChanged { StatusBadge.changed }
                Spacer()
                if let diff = row.difference {
                    DifferenceLabel(seconds: diff)
                } else {
                    Text("not counted")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
            if row.isChanged {
                Text("Changed: " + row.changes.map(\.label).joined(separator: " · "))
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
            cellLine(label: "A", cell: row.a, color: Palette.stageRed)
            cellLine(label: "B", cell: row.b, color: Palette.spotlightDeep)
            if showMarkers && (!row.markersA.isEmpty || !row.markersB.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(row.markersA) { marker in markerLine("A", marker) }
                    ForEach(row.markersB) { marker in markerLine("B", marker) }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.paper))
            }
            ChipButton(title: "Open Segment in Draft", systemImage: "square.and.pencil", action: onOpenInDraft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
    }

    private func cellLine(label: String, cell: ComparisonCell, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(Palette.muted)
                .frame(width: 14)
            if let actual = cell.actual {
                DurationBar(value: Double(actual), maxValue: maxValue, color: color)
                Text(TimeFormat.clock(actual))
                    .font(Typo.monoCaption.weight(.semibold))
                    .foregroundColor(Palette.ink)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Text(cell.statusText)
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func markerLine(_ run: String, _ marker: RunMarker) -> some View {
        HStack(spacing: 6) {
            Image(systemName: marker.type.symbol).foregroundColor(Palette.redInk)
            Text("\(run) · \(TimeFormat.clock(marker.segmentOffsetSeconds)) · \(marker.type.title)\(marker.note.isEmpty ? "" : ": \(marker.note)")")
                .font(Typo.caption)
                .foregroundColor(Palette.ink)
                .lineLimit(2)
        }
    }
}

private struct RunPickerSheet: View {
    @ObservedObject var model: CompareRunsViewModel
    let slot: CompareRunsViewModel.Slot
    let onClose: () -> Void
    @State private var current: CompareRunsViewModel.Slot

    init(model: CompareRunsViewModel, slot: CompareRunsViewModel.Slot, onClose: @escaping () -> Void) {
        self.model = model
        self.slot = slot
        self.onClose = onClose
        _current = State(initialValue: slot)
    }

    var body: some View {
        SheetScaffold(title: "Choose Runs", closeTitle: "Done", onClose: onClose) {
            Picker("Slot", selection: $current) {
                Text("Run A").tag(CompareRunsViewModel.Slot.a)
                Text("Run B").tag(CompareRunsViewModel.Slot.b)
            }
            .pickerStyle(.segmented)
            Text("Same mode only. Two Manual runs of one version give the clearest picture.")
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
            if model.candidates.isEmpty {
                Text("No finished runs for this performance yet.")
                    .font(Typo.callout)
                    .foregroundColor(Palette.muted)
            }
            ForEach(model.candidates) { run in
                let reason = model.blockReason(for: run, slot: current)
                let selected = (current == .a ? model.runAID : model.runBID) == run.id
                Button {
                    model.select(run, for: current)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(selected ? Palette.midnight : Palette.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DateText.short(run.startedAt))
                                .font(Typo.headline)
                                .foregroundColor(Palette.ink)
                            Text("\(run.snapshot.versionDisplayName) · \(run.mode.title) · \(run.outcome?.title ?? "") · \(TimeFormat.clock(run.totalActiveSeconds))")
                                .font(Typo.caption)
                                .foregroundColor(Palette.muted)
                            if let reason {
                                Text(reason)
                                    .font(Typo.caption)
                                    .foregroundColor(Palette.redInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Palette.spotlight.opacity(0.3) : Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(reason != nil)
                .opacity(reason != nil ? 0.55 : 1)
            }
        }
    }
}
