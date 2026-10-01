import Combine
import SwiftUI

@MainActor
final class RunReviewViewModel: ObservableObject {
    @Published private(set) var review: RunReview?
    @Published var reflection = ""
    @Published private(set) var savedReflection = ""
    @Published private(set) var comparablePrevious: RehearsalRun?
    @Published private(set) var versionStillExists = true
    /// "Where to trim" for this run, or why this run can't give one.
    @Published private(set) var trim: Result<TrimHint, TrimHint.Ineligible>?
    @Published var alert: AlertMessage?
    @Published private(set) var deleted = false

    let runID: UUID
    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []
    private var loadedReflection = false

    init(container: AppContainer, runID: UUID) {
        self.container = container
        self.runID = runID
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    var reflectionDirty: Bool { reflection != savedReflection }

    func reload() {
        guard let run = container.rehearsals.run(id: runID) else {
            review = nil
            return
        }
        review = RunReview.build(run: run, markers: container.rehearsals.markers(runID: runID))
        savedReflection = run.reflection
        if !loadedReflection {
            reflection = run.reflection
            loadedReflection = true
        }
        versionStillExists = container.scripts.version(id: run.versionID) != nil
        trim = container.insights.trimHint(runID: run.id)
        comparablePrevious = Self.previousComparable(to: run, among: container.rehearsals.runs(performanceID: run.performanceID, mode: run.mode))
    }

    /// Previous finished run of the same performance and mode — the natural "A" for a comparison.
    /// Prefers the same version, then the most recent.
    private static func previousComparable(to run: RehearsalRun, among runs: [RehearsalRun]) -> RehearsalRun? {
        let earlier: [RehearsalRun] = runs.filter { $0.id != run.id && $0.startedAt < run.startedAt }
        let sameVersion: [RehearsalRun] = earlier.filter { $0.versionID == run.versionID }
        let pool: [RehearsalRun] = sameVersion.isEmpty ? earlier : sameVersion
        return pool.max { $0.startedAt < $1.startedAt }
    }

    func saveReflection() {
        do {
            try container.rehearsals.saveReflection(runID: runID, text: reflection)
            Haptics.success()
        } catch {
            alert = AlertMessage(error)
        }
    }

    func delete() {
        do {
            try container.rehearsals.deleteRun(id: runID)
            deleted = true
        } catch {
            alert = AlertMessage(error)
        }
    }
}

/// Rehearsal Review — actual time per segment, pauses, markers and your own reflection. No scores.
struct RunReviewView: View {
    @StateObject private var model: RunReviewViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var navigator: AppNavigator
    @State private var confirmDelete = false

    init(container: AppContainer, runID: UUID) {
        _model = StateObject(wrappedValue: RunReviewViewModel(container: container, runID: runID))
    }

    var body: some View {
        Group {
            if let review = model.review {
                ScreenScaffold(title: "Rehearsal Review", subtitle: review.run.snapshot.performanceName, backAction: { router.pop() }) {
                    HeaderIconButton(systemName: "square.and.arrow.up", label: "Export run summary") {
                        router.push(.export(ExportPreset(kind: .runSummary, performanceID: review.run.performanceID, runID: review.run.id)))
                    }
                    .disabled(review.run.isLive)
                } content: {
                    content(review)
                }
            } else {
                ScreenScaffold(title: "Rehearsal Review", backAction: { router.pop() }) {
                    EmptyStateView(asset: ArtAsset.notebook, size: CGSize(width: 88, height: 76),
                                   title: "Run not found", message: "This run was deleted.")
                }
            }
        }
        .alert($model.alert)
        .onChange(of: model.deleted) { if $0 { router.pop() } }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Run", role: .destructive) { model.delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its timing, markers and reflection are removed. The script version is not affected.")
        }
    }

    @ViewBuilder
    private func content(_ review: RunReview) -> some View {
        let run = review.run
        summaryHeader(review)
        if run.isLive {
            NoticeBanner(text: "This run is still in progress. Results are final only after you finish or end it.", systemImage: "pause.circle.fill", tone: .spotlight)
            Button {
                navigator.presentStage(runID: run.id)
            } label: {
                Label("Continue Run", systemImage: "play.fill")
            }
            .buttonStyle(.cuePrimary)
        }
        if run.interruptionCount > 0 {
            NoticeBanner(text: "Recovered after \(run.interruptionCount) unexpected close(s). Time while the app was closed isn't counted.",
                         systemImage: "bolt.horizontal.circle.fill", tone: .warning)
        }
        if run.mode == .autoAdvance {
            NoticeBanner(text: "Auto Advance switched segments on the planned schedule. These numbers show how the run followed that schedule — not how long you actually spoke.",
                         systemImage: "timer")
        }
        trimSection
        completedSection(review)
        notCountedSection(review)
        markersSection(review)
        reflectionSection
        actionsSection(review)
    }

    private func summaryHeader(_ review: RunReview) -> some View {
        let run = review.run
        return CueCard(accent: Palette.stageRed) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DateText.short(run.startedAt))
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                    Text(run.snapshot.versionDisplayName)
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    HStack(spacing: 6) {
                        StatusBadge.outcome(run.outcome)
                        StatusBadge(run.mode.shortTitle, systemImage: run.mode.symbol)
                    }
                    if run.isPartial && !run.isLive { StatusBadge.partial }
                }
                Spacer()
                Illustration(ArtAsset.notebook, size: CGSize(width: 88, height: 76))
            }
            HStack(spacing: 10) {
                StatTile(label: "Active", value: TimeFormat.clock(run.totalActiveSeconds))
                StatTile(label: "Paused", value: TimeFormat.clock(run.totalPausedSeconds), caption: "not in active time")
            }
            HStack(spacing: 10) {
                StatTile(label: "Planned (done)", value: TimeFormat.clock(review.plannedForCompleted),
                         caption: "\(review.completed.count) completed segment(s)")
                StatTile(label: "Markers", value: "\(review.markers.count)")
            }
            if let total = review.manualDeviationTotal {
                HStack {
                    Text("Deviation on completed segments")
                        .font(Typo.callout)
                        .foregroundColor(Palette.muted)
                    Spacer()
                    DeviationLabel(seconds: total)
                }
            }
            // The "Where to trim" card below already lists the overruns when this run qualifies.
            if let overrun = review.largestOverrun, !hasTrimCard {
                NoticeBanner(text: "Largest overrun: “\(overrun.segment.title)” ran \(TimeFormat.delta(overrun.deviation)) over its plan.",
                             systemImage: "scissors", tone: .spotlight)
            }
        }
    }

    private var hasTrimCard: Bool {
        if case .success? = model.trim { return true }
        return false
    }

    @ViewBuilder
    private var trimSection: some View {
        switch model.trim {
        case let .success(hint)?:
            TrimHintCard(hint: hint, showsSource: false)
        case let .failure(reason)? where [TrimHint.Ineligible.autoAdvance, .notCompleted, .partialStart].contains(reason):
            NoticeBanner(text: "Where to trim: \(reason.explanation)", systemImage: "scissors")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func completedSection(_ review: RunReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: review.run.mode == .manual ? "Planned vs actual" : "Schedule",
                         trailing: review.completed.isEmpty ? nil : "\(TimeFormat.clock(review.actualForCompleted)) / \(TimeFormat.clock(review.plannedForCompleted))")
            if review.completed.isEmpty {
                CueCard {
                    Text("No segment was completed in this run, so there's no timing to compare.")
                        .font(Typo.callout)
                        .foregroundColor(Palette.muted)
                }
            } else {
                let maxValue = Double(review.completed.map { max($0.actualSeconds, $0.segment.plannedSeconds) }.max() ?? 1)
                ForEach(review.completed) { row in
                    CompletedSegmentRow(row: row, mode: review.run.mode, maxValue: maxValue)
                }
            }
        }
    }

    @ViewBuilder
    private func notCountedSection(_ review: RunReview) -> some View {
        let groups: [(String, String, [ReviewRow])] = [
            ("Skipped", "Optional, skipped during the run", review.skipped),
            ("Unfinished", "On stage when the run ended", review.unfinished),
            ("Not reached", "The run ended before these", review.notReached),
            ("Excluded", "Optional, left out at setup", review.excluded),
            ("Before start", "Before the chosen start segment", review.beforeStart)
        ].filter { !$0.2.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Not counted in timing")
                CueCard {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(group.0).font(Typo.headline).foregroundColor(Palette.ink)
                                Text(group.1).font(Typo.caption).foregroundColor(Palette.muted)
                            }
                            ForEach(group.2) { row in
                                HStack {
                                    Text("\(row.position). \(row.segment.title)")
                                        .font(Typo.callout)
                                        .foregroundColor(Palette.ink)
                                    Spacer()
                                    Text("plan \(TimeFormat.clock(row.segment.plannedSeconds))")
                                        .font(Typo.monoCaption)
                                        .foregroundColor(Palette.muted)
                                }
                            }
                        }
                    }
                    Text("These segments are listed separately and never count as zero in comparisons.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func markersSection(_ review: RunReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Markers", trailing: "\(review.markers.count)")
            CueCard {
                if review.markers.isEmpty {
                    Text("No markers were dropped in this run.")
                        .font(Typo.callout)
                        .foregroundColor(Palette.muted)
                } else {
                    let titles = Dictionary(review.run.snapshot.segments.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
                    ForEach(review.markers.prefix(4)) { marker in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: marker.type.symbol)
                                .foregroundColor(Palette.redInk)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(titles[marker.segmentID] ?? "—") · \(TimeFormat.clock(marker.segmentOffsetSeconds))")
                                    .font(Typo.callout.weight(.semibold))
                                    .foregroundColor(Palette.ink)
                                Text(marker.note.isEmpty ? marker.type.title : "\(marker.type.title): \(marker.note)")
                                    .font(Typo.caption)
                                    .foregroundColor(Palette.muted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if review.markers.count > 4 {
                        Text("+\(review.markers.count - 4) more")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
                ChipButton(title: "Open Markers", systemImage: "bookmark") {
                    router.push(.markers(runID: review.run.id))
                }
            }
        }
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Reflection")
            CueCard {
                CueTextEditor(label: "Your notes on this run", text: $model.reflection,
                              placeholder: "What felt long? What would you cut or clarify next time?",
                              limit: Limits.reflectionMax, minHeight: 110,
                              hint: "Private. Left out of exports unless you include it.")
                Button {
                    model.saveReflection()
                } label: {
                    Label(model.reflectionDirty ? "Save Reflection" : "Reflection Saved", systemImage: model.reflectionDirty ? "tray.and.arrow.down" : "checkmark")
                }
                .buttonStyle(model.reflectionDirty ? .cuePrimary : .cueSecondary)
                .disabled(!model.reflectionDirty)
            }
        }
    }

    private func actionsSection(_ review: RunReview) -> some View {
        let run = review.run
        return VStack(spacing: 10) {
            SectionTitle(title: "Next steps")
            Button {
                router.push(.rehearsalSetup(RehearsalPreset(performanceID: run.performanceID, versionID: run.versionID, mode: run.mode)))
            } label: {
                Label("Rehearse Same Version", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.cuePrimary)
            .disabled(run.isLive || !model.versionStillExists)

            HStack(spacing: 10) {
                Button {
                    router.push(.compare(ComparePreset(performanceID: run.performanceID, runA: model.comparablePrevious?.id, runB: run.id)))
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(.cueSecondary)
                .disabled(run.isLive)

                Button {
                    router.push(.versions(performanceID: run.performanceID, highlight: run.versionID))
                } label: {
                    Label("Edit New Version", systemImage: "square.and.pencil")
                }
                .buttonStyle(.cueSecondary)
            }
            Button {
                router.push(.segmentHistory(performanceID: run.performanceID))
            } label: {
                Label("Segment History", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.cueSecondary)
            if model.comparablePrevious == nil && !run.isLive {
                Text("Compare needs another finished \(run.mode.title) run of this performance.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
            Text("The result stays as recorded — an unfinished run can't become Completed without a new run.")
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !run.isLive {
                Button {
                    confirmDelete = true
                } label: {
                    Label("Delete Run", systemImage: "trash")
                }
                .buttonStyle(.cueDestructive)
            }
        }
    }
}

private struct CompletedSegmentRow: View {
    let row: ReviewRow
    let mode: RunMode
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(row.position). \(row.segment.title)")
                    .font(Typo.headline)
                    .foregroundColor(Palette.ink)
                if row.segment.isOptional { StatusBadge.optional }
                Spacer()
                if !row.markers.isEmpty {
                    StatusBadge("\(row.markers.count)", systemImage: "bookmark.fill", style: .red)
                }
            }
            HStack(spacing: 14) {
                labeled("Plan", TimeFormat.clock(row.segment.plannedSeconds))
                labeled("Actual", TimeFormat.clock(row.actualSeconds))
                Spacer()
                if mode == .manual {
                    DeviationLabel(seconds: row.deviation)
                } else if row.record.advancedBy == .autoSchedule {
                    Label("On schedule", systemImage: "checkmark.circle.fill")
                        .font(Typo.captionBold)
                        .foregroundColor(Palette.blueInk)
                } else {
                    Label("Advanced early \(TimeFormat.delta(row.deviation))", systemImage: "forward.fill")
                        .font(Typo.captionBold)
                        .foregroundColor(Palette.blueInk)
                }
            }
            DurationBar(value: Double(row.actualSeconds), maxValue: maxValue,
                        color: mode == .manual && row.isExceeded ? Palette.stageRed : Palette.midnightLift,
                        marker: Double(row.segment.plannedSeconds))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(Typo.eyebrow).foregroundColor(Palette.muted)
            Text(value).font(Typo.monoHeadline).foregroundColor(Palette.ink)
        }
    }
}
