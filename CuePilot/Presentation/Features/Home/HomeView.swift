import SwiftUI

/// Home — opens the latest performance and any unfinished run.
struct HomeView: View {
    @StateObject private var model: HomeViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var navigator: AppNavigator
    @State private var confirmEndRun = false

    init(container: AppContainer) {
        _model = StateObject(wrappedValue: HomeViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(spacing: 16) {
                    if let live = model.liveRun {
                        liveRunCard(live)
                    }
                    if let summary = model.summary {
                        currentPerformanceCard(summary)
                    } else {
                        firstPerformanceCard
                    }
                    quickActions
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, -28)
                .padding(.bottom, 32)
                .readableWidth()
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .overlay(alignment: .top) {
            // Fixed blue band behind the light status bar, whatever the scroll position.
            Color.clear.frame(height: 0).background(Palette.midnightDeep.ignoresSafeArea(edges: .top))
        }
        .alert($model.alert)
        .confirmationDialog("End the unfinished run?", isPresented: $confirmEndRun, titleVisibility: .visible) {
            Button("End Run Early") { model.endLiveRun() }
            Button("Discard Run", role: .destructive) { model.discardLiveRun() }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("Ending keeps completed segments. Discarding deletes the run and its markers.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            StageHeroBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CUE PILOT")
                            .font(Typo.eyebrow)
                            .tracking(2)
                            .foregroundColor(Palette.spotlight)
                        Text("Rehearsal desk")
                            .font(Typo.display(26))
                            .foregroundColor(.white)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    HeaderIconButton(systemName: "gearshape.fill", label: "Settings") {
                        router.push(.settings)
                    }
                }
                HStack(alignment: .bottom, spacing: 4) {
                    tipBubble
                    Illustration(ArtAsset.flickDirector, size: CGSize(width: 140, height: 160))
                }
                .padding(.top, 8)
            }
            .padding(.leading, 76)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var tipBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Flick says", systemImage: "lightbulb.fill")
                .font(Typo.captionBold)
                .foregroundColor(Palette.spotlight)
            Text(model.tip)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .padding(.bottom, 30)
        .accessibilityElement(children: .combine)
    }

    // MARK: Cards

    private func liveRunCard(_ live: HomeViewModel.LiveRunInfo) -> some View {
        CueCard(accent: live.wasInterrupted ? Palette.stageRed : Palette.spotlight) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(live.wasInterrupted ? "INTERRUPTED RUN" : "SUSPENDED RUN")
                        .font(Typo.eyebrow)
                        .tracking(1)
                        .foregroundColor(live.wasInterrupted ? Palette.redInk : Palette.muted)
                    Text(live.run.snapshot.performanceName)
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text("\(live.run.snapshot.versionDisplayName) · \(live.run.mode.title)")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
                StatusBadge("Paused", systemImage: "pause.fill", style: .yellow)
            }
            HStack(spacing: 10) {
                StatTile(label: "Segment", value: "\(live.position)/\(live.total)", caption: live.run.currentSegment?.title)
                StatTile(label: "Active", value: TimeFormat.clock(live.run.totalActiveSeconds))
            }
            if live.wasInterrupted {
                NoticeBanner(
                    text: "Restored from the last saved point. Time while the app was closed isn't counted.",
                    systemImage: "bolt.horizontal.circle.fill", tone: .warning
                )
            }
            HStack(spacing: 10) {
                Button {
                    navigator.presentStage(runID: live.run.id)
                } label: {
                    Label("Continue Run", systemImage: "play.fill")
                }
                .buttonStyle(.cuePrimary)
                Button("End…") { confirmEndRun = true }
                    .buttonStyle(.cue(.secondary, fullWidth: false))
            }
        }
    }

    private func currentPerformanceCard(_ summary: PerformanceSummary) -> some View {
        CueCard(accent: Palette.stageRed) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PERFORMANCE")
                        .font(Typo.eyebrow)
                        .tracking(1)
                        .foregroundColor(Palette.redInk)
                    Text(summary.performance.name)
                        .font(Typo.title)
                        .foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusBadge(summary.performance.type.title, systemImage: summary.performance.type.symbol)
            }
            VStack(spacing: 10) {
                InfoRow(label: "Latest Version", value: latestVersionText(summary), systemImage: "square.stack.3d.up")
                InfoRow(
                    label: "Planned Duration",
                    value: summary.plannedTotalSeconds.map(TimeFormat.clock) ?? "Not Set Up",
                    systemImage: "clock",
                    valueColor: summary.plannedTotalSeconds == nil ? Palette.muted : Palette.ink,
                    monospaced: true
                )
                if let target = summary.performance.targetTotalSeconds {
                    InfoRow(label: "Personal Target", value: TimeFormat.clock(target), systemImage: "flag", monospaced: true)
                }
                lastRunRow(summary)
            }
            if let hint = model.trimHint {
                TrimHintSummaryRow(hint: hint) {
                    router.push(.segmentHistory(performanceID: summary.performance.id))
                }
            } else if model.hasManualRuns {
                ChipButton(title: "Segment History", systemImage: "chart.bar.xaxis") {
                    router.push(.segmentHistory(performanceID: summary.performance.id))
                }
            }
            if !summary.canRehearse {
                NoticeBanner(text: summary.segmentCount == 0
                             ? "Add segments and publish a version to rehearse."
                             : "Publish the draft to rehearse it.")
            }
            HStack(spacing: 10) {
                Button {
                    router.push(.rehearsalSetup(RehearsalPreset(performanceID: summary.performance.id)))
                } label: {
                    Label("Rehearse", systemImage: "play.circle.fill")
                }
                .buttonStyle(.cuePrimary)
                .disabled(!summary.canRehearse || model.liveRun != nil)

                Button {
                    router.push(.performanceEditor(summary.performance.id))
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.cue(.secondary, fullWidth: false))
            }
            if model.liveRun != nil && summary.canRehearse {
                Text("Finish or end the unfinished run before starting a new one.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
        }
    }

    @ViewBuilder
    private func lastRunRow(_ summary: PerformanceSummary) -> some View {
        if let run = summary.lastRun {
            Button {
                router.push(.review(runID: run.id))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Palette.muted)
                        .frame(width: 20)
                    Text("Last Run")
                        .font(Typo.callout)
                        .foregroundColor(Palette.muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(DateText.relative(run.endedAt ?? run.startedAt)) · \(TimeFormat.clock(run.totalActiveSeconds))")
                            .font(Typo.monoHeadline)
                            .foregroundColor(Palette.ink)
                        StatusBadge.outcome(run.outcome)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Palette.muted)
                }
                .frame(minHeight: Metrics.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the rehearsal review")
        } else {
            InfoRow(label: "Last Run", value: "Not rehearsed yet", systemImage: "clock.arrow.circlepath", valueColor: Palette.muted)
        }
    }

    private func latestVersionText(_ summary: PerformanceSummary) -> String {
        guard let latest = summary.latestVersion else { return "—" }
        return "\(latest.shortName) · \(latest.isDraft ? "Draft" : "Published")"
    }

    private var firstPerformanceCard: some View {
        CueCard(accent: Palette.stageRed) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.hasAnyPerformance ? "No active performance" : "Create Your First Performance")
                    .font(Typo.title)
                    .foregroundColor(Palette.ink)
                Text(model.hasAnyPerformance
                     ? "Everything is archived. Restore a performance from the Library or start a new one."
                     : "A talk, a set, a toast or a reading — split it into segments with a planned time and a short cue.")
                    .font(Typo.callout)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.push(.performanceEditor(nil))
                } label: {
                    Label("Create Performance", systemImage: "plus")
                }
                .buttonStyle(.cuePrimary)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Stage desk")
            HStack(spacing: 10) {
                quickAction(title: "New Performance", systemImage: "plus.rectangle.on.rectangle") {
                    router.push(.performanceEditor(nil))
                }
                quickAction(title: "Library", systemImage: "books.vertical", badge: model.activeCount > 0 ? "\(model.activeCount)" : nil) {
                    router.push(.library(showArchived: false))
                }
            }
            HStack(spacing: 10) {
                quickAction(title: "Recent Runs", systemImage: "list.bullet.rectangle") {
                    navigator.selectedTab = .runs
                }
                quickAction(title: "Settings", systemImage: "gearshape") {
                    router.push(.settings)
                }
            }
        }
    }

    private func quickAction(title: String, systemImage: String, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.midnight)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.spotlight.opacity(0.45)))
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(Typo.monoCaption.weight(.bold))
                        .foregroundColor(Palette.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
