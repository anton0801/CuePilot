import Combine
import SwiftUI

@MainActor
final class RehearsalSetupViewModel: ObservableObject {
    @Published private(set) var performances: [Performance] = []
    @Published private(set) var versions: [ScriptVersion] = []
    @Published private(set) var currentVersionID: UUID?
    @Published private(set) var plan: RehearsalPlan?
    @Published private(set) var liveRun: RehearsalRun?
    @Published private(set) var hasDraft = false
    @Published var alert: AlertMessage?

    @Published var performanceID: UUID?
    @Published var versionID: UUID?
    @Published var mode: RunMode
    @Published var startSegmentID: UUID?
    @Published var includeOptional = true

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, preset: RehearsalPreset) {
        self.container = container
        mode = preset.mode ?? .manual
        performanceID = preset.performanceID ?? container.performances.currentPerformance()?.id
        versionID = preset.versionID
        reload()

        container.databaseChanges
            .dropFirst()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        // Selection changes cascade: performance → version → plan.
        // @Published emits before the value is stored, so hop to the next run loop turn before reading it.
        $performanceID.dropFirst().removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.performanceChanged() }
            .store(in: &cancellables)
        Publishers.CombineLatest3($versionID.removeDuplicates(), $startSegmentID.removeDuplicates(), $includeOptional.removeDuplicates())
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputePlan() }
            .store(in: &cancellables)
    }

    var selectedPerformance: Performance? { performances.first { $0.id == performanceID } }
    var selectedVersion: ScriptVersion? { versions.first { $0.id == versionID } }
    var hasOptional: Bool { selectedVersion?.segments.contains(where: \.isOptional) ?? false }
    var canStart: Bool { liveRun == nil && (plan?.isRunnable ?? false) }

    var targetGap: Int? {
        guard let target = selectedPerformance?.targetTotalSeconds, let plan else { return nil }
        return plan.plannedSeconds - target
    }

    private func reload() {
        performances = container.performances.performances(archived: false)
        liveRun = container.rehearsals.liveRun()
        if let performanceID, !performances.contains(where: { $0.id == performanceID }) {
            self.performanceID = performances.first?.id
        } else if performanceID == nil {
            performanceID = performances.first?.id
        }
        loadVersions(keepSelection: true)
    }

    private func performanceChanged() {
        startSegmentID = nil
        loadVersions(keepSelection: false)
    }

    private func loadVersions(keepSelection: Bool) {
        guard let performanceID else {
            versions = []
            versionID = nil
            plan = nil
            hasDraft = false
            return
        }
        versions = container.scripts.publishedVersions(performanceID: performanceID)
        currentVersionID = container.scripts.currentPublished(performanceID: performanceID)?.id
        hasDraft = container.scripts.draft(performanceID: performanceID) != nil
        if !(keepSelection && versions.contains(where: { $0.id == versionID })) {
            versionID = currentVersionID
        }
        recomputePlan()
    }

    private func recomputePlan() {
        guard let performanceID, let versionID else {
            plan = nil
            return
        }
        let config = RehearsalConfig(performanceID: performanceID, versionID: versionID, mode: mode,
                                     startSegmentID: startSegmentID, includeOptional: includeOptional)
        plan = container.rehearsals.plan(for: config)
        if let startSegmentID, plan?.startCandidates.contains(where: { $0.id == startSegmentID }) != true {
            self.startSegmentID = nil
        }
    }

    func start() -> UUID? {
        guard let performanceID, let versionID else { return nil }
        let config = RehearsalConfig(performanceID: performanceID, versionID: versionID, mode: mode,
                                     startSegmentID: plan?.startSegmentID, includeOptional: includeOptional)
        do {
            let run = try container.rehearsals.start(config)
            Haptics.success()
            return run.id
        } catch {
            alert = AlertMessage(error)
            return nil
        }
    }

    func endLiveRun() {
        do { try container.rehearsals.endLiveRun() } catch { alert = AlertMessage(error) }
    }

    func discardLiveRun() {
        do { try container.rehearsals.discardLiveRun() } catch { alert = AlertMessage(error) }
    }
}

/// Rehearsal Setup — choose performance, published version and how segments advance. The mode is visible before Start.
struct RehearsalSetupView: View {
    @StateObject private var model: RehearsalSetupViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var navigator: AppNavigator
    let isTabRoot: Bool
    @State private var confirmStart = false
    @State private var confirmEndLive = false

    init(container: AppContainer, preset: RehearsalPreset, isTabRoot: Bool) {
        _model = StateObject(wrappedValue: RehearsalSetupViewModel(container: container, preset: preset))
        self.isTabRoot = isTabRoot
    }

    var body: some View {
        ScreenScaffold(title: isTabRoot ? "Rehearse" : "Rehearsal Setup",
                       subtitle: "Pick a published version and a mode",
                       backAction: isTabRoot ? nil : { router.pop() }) {
            if let live = model.liveRun {
                liveRunCard(live)
            }
            if model.performances.isEmpty {
                EmptyStateView(asset: ArtAsset.stageTimer, size: CGSize(width: 80, height: 88),
                               title: "Nothing to rehearse yet",
                               message: "Create a performance, add segments and publish a version first.",
                               actionTitle: "Create Performance") { router.push(.performanceEditor(nil)) }
            } else {
                selectionCard
                if model.selectedPerformance != nil && model.versions.isEmpty {
                    NoticeBanner(text: "“\(model.selectedPerformance?.name ?? "")” has no published version yet. Runs always use a published script.",
                                 systemImage: "lock.open.fill", tone: .warning)
                    Button {
                        if let id = model.performanceID { router.push(.performanceEditor(id)) }
                    } label: {
                        Label("Edit Draft", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.cuePrimary)
                } else {
                    modeCard
                    optionsCard
                    summaryCard
                    actions
                }
            }
        }
        .alert($model.alert)
        .confirmationDialog(confirmTitle, isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Confirm Start") {
                if let runID = model.start() { navigator.presentStage(runID: runID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A snapshot of \(model.selectedVersion?.shortName ?? "this version") is saved with the run, so later edits never change its results.")
        }
        .confirmationDialog("End the unfinished run?", isPresented: $confirmEndLive, titleVisibility: .visible) {
            Button("End Run Early") { model.endLiveRun() }
            Button("Discard Run", role: .destructive) { model.discardLiveRun() }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("Only one unfinished run can exist. Ending keeps completed segments; discarding deletes the run and its markers.")
        }
    }

    private var confirmTitle: String {
        let plan = model.plan
        return "Start \(model.mode.title) · \(plan?.included.count ?? 0) segments · \(TimeFormat.clock(plan?.plannedSeconds ?? 0))"
    }

    private func liveRunCard(_ run: RehearsalRun) -> some View {
        CueCard(accent: Palette.spotlight) {
            Text(run.interruptionCount > 0 ? "INTERRUPTED RUN" : "UNFINISHED RUN")
                .font(Typo.eyebrow)
                .foregroundColor(run.interruptionCount > 0 ? Palette.redInk : Palette.muted)
            Text("\(run.snapshot.performanceName) · \(run.snapshot.versionDisplayName)")
                .font(Typo.headline)
                .foregroundColor(Palette.ink)
            Text("Paused on “\(run.currentSegment?.title ?? "—")” · \(TimeFormat.clock(run.totalActiveSeconds)) active")
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
            HStack(spacing: 10) {
                Button {
                    navigator.presentStage(runID: run.id)
                } label: {
                    Label("Continue Existing Run", systemImage: "play.fill")
                }
                .buttonStyle(.cuePrimary)
                Button("End…") { confirmEndLive = true }
                    .buttonStyle(.cue(.secondary, fullWidth: false))
            }
        }
    }

    private var selectionCard: some View {
        CueCard {
            pickerRow(label: "Performance", required: true, value: model.selectedPerformance?.name ?? "Choose") {
                ForEach(model.performances) { performance in
                    Button(performance.name) { model.performanceID = performance.id }
                }
            }
            pickerRow(label: "Published Version", required: true, value: versionTitle(model.selectedVersion)) {
                ForEach(model.versions) { version in
                    Button(versionTitle(version)) { model.versionID = version.id }
                }
            }
            .disabled(model.versions.isEmpty)
            if model.hasDraft {
                Text("A newer draft exists. Publish it to rehearse its changes.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
        }
    }

    private func versionTitle(_ version: ScriptVersion?) -> String {
        guard let version else { return "None published" }
        return version.displayName + (version.id == model.currentVersionID ? " (Current)" : "")
    }

    private func pickerRow<Items: View>(label: String, required: Bool, value: String, @ViewBuilder items: () -> Items) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: required)
            Menu {
                items()
            } label: {
                HStack {
                    Text(value)
                        .font(Typo.body)
                        .foregroundColor(Palette.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.blueInk)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1.5))
            }
            .accessibilityLabel("\(label): \(value)")
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Mode")
            HStack(spacing: 10) {
                ForEach(RunMode.allCases) { mode in
                    ModeOption(mode: mode, isSelected: model.mode == mode) { model.mode = mode }
                }
            }
            Text(model.mode.explanation)
                .font(Typo.callout)
                .foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.spotlight.opacity(0.25)))
            Text("Manual and Auto runs are kept apart in comparisons.")
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
        }
    }

    private var optionsCard: some View {
        CueCard {
            pickerRow(label: "Start Segment", required: false, value: startTitle) {
                ForEach(Array((model.plan?.startCandidates ?? []).enumerated()), id: \.element.id) { index, segment in
                    Button("\(index + 1). \(segment.title)") { model.startSegmentID = segment.id }
                }
            }
            if model.hasOptional {
                Toggle(isOn: $model.includeOptional) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Optional Segments")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Palette.ink)
                        Text("You can still skip an optional segment during the run.")
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
                .tint(Palette.midnight)
            }
        }
    }

    private var startTitle: String {
        guard let plan = model.plan, let id = plan.startSegmentID,
              let index = plan.startCandidates.firstIndex(where: { $0.id == id }) else { return "First segment" }
        return "\(index + 1). \(plan.startCandidates[index].title)"
    }

    private var summaryCard: some View {
        CueCard(accent: Palette.stageRed) {
            HStack(alignment: .top, spacing: 14) {
                Illustration(ArtAsset.stageTimer, size: CGSize(width: 80, height: 88))
                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET SUMMARY")
                        .font(Typo.eyebrow)
                        .foregroundColor(Palette.redInk)
                    Text(TimeFormat.clock(model.plan?.plannedSeconds ?? 0))
                        .font(Typo.timer(34))
                        .foregroundColor(Palette.ink)
                    Text("planned across \(model.plan?.included.count ?? 0) segment(s)")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                    HStack(spacing: 6) {
                        StatusBadge.mode(model.mode)
                        if model.plan?.isPartial == true { StatusBadge.partial }
                    }
                }
            }
            if let target = model.selectedPerformance?.targetTotalSeconds, let gap = model.targetGap {
                InfoRow(label: "Personal target", value: "\(TimeFormat.clock(target)) (\(gap == 0 ? "matches" : TimeFormat.delta(gap)))",
                        systemImage: "flag", monospaced: true)
            }
            if let plan = model.plan {
                if plan.isPartial {
                    Text("Partial Run: \(plan.beforeStart.count) segment(s) before the start won't be rehearsed.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
                if !plan.excludedOptional.isEmpty {
                    Text("Excluded optional: " + plan.excludedOptional.map(\.title).joined(separator: ", "))
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                confirmStart = true
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.cuePrimary)
            .disabled(!model.canStart)
            if model.liveRun != nil {
                Text("Continue, end or discard the unfinished run first — only one can exist at a time.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
            HStack(spacing: 10) {
                Button {
                    navigator.sheet = .stagePreview(versionID: model.versionID)
                } label: {
                    Label("Preview Stage", systemImage: "eye")
                }
                .buttonStyle(.cueSecondary)
                Button {
                    if let id = model.performanceID { router.push(.performanceEditor(id)) }
                } label: {
                    Label("Edit Draft", systemImage: "square.and.pencil")
                }
                .buttonStyle(.cueSecondary)
            }
        }
    }
}

private struct ModeOption: View {
    let mode: RunMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                }
                Text(mode.title)
                    .font(Typo.headline)
                    .multilineTextAlignment(.leading)
                Text(mode == .manual ? "Measures real timing" : "Practice to a schedule")
                    .font(Typo.caption)
                    .multilineTextAlignment(.leading)
                    .opacity(0.85)
            }
            .foregroundColor(isSelected ? .white : Palette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.midnight : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.spotlight : Palette.rule, lineWidth: isSelected ? 2.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
