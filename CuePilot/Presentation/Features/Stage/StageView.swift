import SwiftUI

/// Stage Mode — almost the whole screen is a real, large timer. Two big zones: Pause and Next.
struct StageView: View {
    @StateObject private var model: StageViewModel
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var container: AppContainer
    /// The markers sheet has no navigation of its own; it still needs a router in its environment.
    @StateObject private var sheetRouter = Router()

    init(container: AppContainer, runID: UUID) {
        _model = StateObject(wrappedValue: StageViewModel(container: container, runID: runID))
    }

    var body: some View {
        ZStack {
            StageBackdrop()
            if let display = model.display {
                StageLayout(
                    display: display,
                    scale: container.settings.stageTextSize.scale,
                    notices: notices,
                    actions: StageActions(
                        leave: model.leaveStage,
                        end: model.requestEnd,
                        togglePause: model.togglePause,
                        next: { model.next(displayedIndex: display.index) },
                        skipOptional: { model.skipOptional(displayedIndex: display.index) },
                        marker: model.addMarker,
                        markers: model.openMarkers
                    )
                )
            } else if model.missingRun {
                missingRunView
            }

            if let toast = model.toast {
                VStack {
                    ToastView(text: toast, systemImage: "bookmark.fill")
                        .padding(.top, 70)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            if let pending = model.pendingFinish, let display = model.display {
                FinishCard(display: display, skipping: pending == .skipCurrent, onFinish: model.confirmFinish, onKeepGoing: model.keepGoing)
            }
        }
        .onAppear { model.onAppear(keepScreenAwake: container.settings.keepScreenAwake) }
        .onDisappear { model.onDisappear() }
        .onChange(of: model.exit) { exit in
            switch exit {
            case .leave: navigator.closeStage(reviewRunID: nil)
            case let .review(runID): navigator.closeStage(reviewRunID: runID)
            case nil: break
            }
        }
        .confirmationDialog("End this run?", isPresented: $model.showEndDialog, titleVisibility: .visible) {
            if model.display?.isLast == true {
                Button("Finish Run") { model.finishFromEndDialog() }
            }
            Button("End Early", role: .destructive) { model.endEarly() }
            Button("Continue", role: .cancel) { model.continueAfterEnd() }
        } message: {
            Text("Ending early keeps completed segments. The segment on stage is saved as unfinished and the rest as not reached — none of them count toward timing.")
        }
        .sheet(isPresented: $model.showMarkers) {
            MarkersView(container: container, runID: model.runID, context: .stageSheet(onClose: { model.showMarkers = false }))
                .environmentObject(container)
                .environmentObject(navigator)
                .environmentObject(sheetRouter)
        }
        .alert($model.alert)
    }

    private var notices: [StageNotice] {
        var list: [StageNotice] = []
        if model.showInterruptedNotice {
            list.append(StageNotice(id: "interrupted", symbol: "bolt.horizontal.circle.fill",
                                    text: "Recovered from the last saved point after the app closed unexpectedly. Time while it was closed isn't counted. Resume when ready."))
        }
        if model.showAwayNotice && model.isPaused {
            list.append(StageNotice(id: "away", symbol: "pause.circle.fill",
                                    text: "Paused automatically while you were away. Tap Resume to continue."))
        }
        return list
    }

    private var missingRunView: some View {
        VStack(spacing: 16) {
            Text("This run is no longer in progress.")
                .font(Typo.title)
                .foregroundColor(.white)
            Button("Close") { navigator.closeStage(reviewRunID: nil) }
                .buttonStyle(.cuePrimary)
                .frame(maxWidth: 220)
        }
        .padding()
    }
}

struct StageActions {
    var leave: () -> Void = {}
    var end: () -> Void = {}
    var togglePause: () -> Void = {}
    var next: () -> Void = {}
    var skipOptional: () -> Void = {}
    var marker: () -> Void = {}
    var markers: () -> Void = {}

    static let inert = StageActions()
}

struct StageNotice: Identifiable, Equatable {
    let id: String
    let symbol: String
    let text: String
}

/// Static backdrop: midnight with a soft spotlight pool. No moving particles.
struct StageBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.midnightDeep, Palette.midnight, Palette.midnightDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.spotlight.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.0), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// Shared by live Stage Mode and the static previews.
struct StageLayout: View {
    let display: StageDisplay
    let scale: Double
    var notices: [StageNotice] = []
    var actions: StageActions
    var isPreview = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height * 1.1 {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        topBar
                        segmentHeader
                        cueCard
                        noticeStack
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        timerBlock
                        totalsRow
                        nextRow
                        Spacer(minLength: 0)
                        utilityRow
                        primaryZones(height: 96)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    segmentHeader
                    cueCard
                    noticeStack
                    timerBlock
                    totalsRow
                    nextRow
                    utilityRow
                    primaryZones(height: min(124, max(88, proxy.size.height * 0.14)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(maxWidth: Metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundColor(.white)
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 10) {
            HeaderIconButton(systemName: "chevron.down", label: "Leave stage, keep run paused", action: actions.leave)
            StatusBadge(display.mode.title, systemImage: display.mode.symbol, style: .onBlue)
            Spacer()
            Text("\(display.position) / \(display.total)")
                .font(Typo.monoHeadline)
                .foregroundColor(Palette.onBlueMuted)
                .accessibilityLabel("Segment \(display.position) of \(display.total)")
            Button(action: actions.end) {
                Text("End")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: Metrics.minTap)
                    .background(Capsule().fill(Palette.stageRed))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Finish, end early or continue")
        }
    }

    private var segmentHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("NOW")
                    .font(Typo.eyebrow)
                    .tracking(1.6)
                    .foregroundColor(Palette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.spotlight))
                if display.isOptional {
                    StatusBadge("Optional", systemImage: "circle.dashed", style: .onBlue)
                }
                if isPreview {
                    StatusBadge("Preview · clock not running", style: .onBlue)
                }
            }
            Text(display.title)
                .font(Typo.display(26 * scale))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var cueCard: some View {
        ScrollView(showsIndicators: false) {
            Text(display.cue.trimmed.isEmpty ? "No cue for this segment." : display.cue)
                .font(.system(size: 21 * scale, weight: .medium, design: .rounded))
                .foregroundColor(display.cue.trimmed.isEmpty ? Palette.onBlueMuted : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
        .frame(minHeight: 60, maxHeight: 190 * scale)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.spotlight.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel("Cue: \(display.cue)")
    }

    @ViewBuilder
    private var noticeStack: some View {
        ForEach(notices) { notice in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: notice.symbol).foregroundColor(Palette.spotlight)
                Text(notice.text)
                    .font(Typo.callout)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.stageRed.opacity(0.28)))
            .accessibilityElement(children: .combine)
        }
    }

    private var timerBlock: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Text(TimeFormat.clock(display.elapsed))
                    .font(Typo.timer(104 * min(scale, 1.25), weight: .heavy))
                    .foregroundColor(timerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity)
                    .opacity(display.isPaused ? 0.6 : 1)
                if display.isPaused {
                    Label("PAUSED", systemImage: "pause.fill")
                        .font(Typo.captionBold)
                        .foregroundColor(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.spotlight))
                }
            }
            HStack(spacing: 8) {
                Text("of \(TimeFormat.clock(display.planned)) planned")
                    .font(Typo.monoHeadline)
                    .foregroundColor(Palette.onBlueMuted)
                Spacer()
                statusPill
            }
            progressBar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timerAccessibility)
    }

    private var timerColor: Color {
        display.mode == .manual && display.isExceeded ? Color(hex: 0xFFB3B0) : Palette.spotlight
    }

    @ViewBuilder
    private var statusPill: some View {
        if display.mode == .manual && display.isExceeded {
            // Exceeded is spelled out and has its own symbol, not just a colour.
            Label("EXCEEDED \(TimeFormat.delta(display.elapsed - display.planned))", systemImage: "exclamationmark.triangle.fill")
                .font(Typo.monoCaption.weight(.heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Palette.stageRed))
        } else if display.mode == .autoAdvance {
            Label(display.isLast ? "Run ends in \(TimeFormat.clock(display.remaining))" : "Next in \(TimeFormat.clock(display.remaining))",
                  systemImage: "timer")
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(Palette.spotlight)
        } else {
            Label("\(TimeFormat.clock(display.remaining)) left", systemImage: "hourglass")
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(Palette.spotlight)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(display.mode == .manual && display.isExceeded ? Palette.stageRed : Palette.spotlight)
                    .frame(width: max(6, proxy.size.width * CGFloat(display.progress)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var timerAccessibility: String {
        var text = "Segment time \(TimeFormat.spoken(display.elapsed)) of \(TimeFormat.spoken(display.planned)) planned."
        if display.mode == .manual && display.isExceeded {
            text += " Exceeded by \(TimeFormat.spoken(display.elapsed - display.planned))."
        } else {
            text += " \(TimeFormat.spoken(max(0, display.remaining))) left."
        }
        if display.isPaused { text += " Paused." }
        return text
    }

    private var totalsRow: some View {
        HStack(spacing: 10) {
            totalTile(label: "Total active", value: TimeFormat.clock(display.totalActive), caption: "of \(TimeFormat.clock(display.plannedTotal))")
            totalTile(label: "Paused", value: TimeFormat.clock(display.totalPaused), caption: "not counted")
        }
    }

    private func totalTile(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Typo.eyebrow)
                .tracking(0.8)
                .foregroundColor(Palette.onBlueMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Typo.timer(22 * min(scale, 1.2)))
                    .foregroundColor(.white)
                Text(caption)
                    .font(Typo.monoCaption)
                    .foregroundColor(Palette.onBlueMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private var nextRow: some View {
        HStack(spacing: 8) {
            Text(display.isLast ? "LAST" : "NEXT")
                .font(Typo.eyebrow)
                .tracking(1.2)
                .foregroundColor(Palette.onBlueMuted)
            Text(display.isLast ? "This is the last segment — Next finishes the run" : (display.nextTitle ?? ""))
                .font(.system(size: 17 * scale, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var utilityRow: some View {
        HStack(spacing: 10) {
            utilityButton(title: "Marker", systemImage: "bookmark.fill", badge: display.markerCount, tint: Palette.stageRed, action: actions.marker)
                .accessibilityHint("Saves a marker at the current time")
            if display.isOptional {
                utilityButton(title: "Skip Optional", systemImage: "forward.end", tint: .white, action: actions.skipOptional)
            }
            utilityButton(title: "Markers", systemImage: "list.bullet", tint: .white, action: actions.markers)
                .opacity(display.isPaused ? 1 : 0.45)
                .accessibilityHint(display.isPaused ? "Edit markers" : "Pause first to edit markers")
        }
    }

    private func utilityButton(title: String, systemImage: String, badge: Int = 0, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundColor(tint)
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if badge > 0 {
                    Text("\(badge)")
                        .font(Typo.monoCaption.weight(.bold))
                        .foregroundColor(Palette.ink)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Palette.spotlight))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryZones(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button(action: actions.togglePause) {
                VStack(spacing: 6) {
                    Image(systemName: display.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                    Text(display.isPaused ? "Resume" : "Pause")
                        .font(Typo.display(20))
                }
                .foregroundColor(display.isPaused ? Palette.ink : .white)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(display.isPaused ? Palette.spotlight : Palette.midnightLift)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(StageZoneStyle())
            .accessibilityLabel(display.isPaused ? "Resume" : "Pause")

            Button(action: actions.next) {
                VStack(spacing: 6) {
                    Image(systemName: display.isLast ? "flag.checkered" : "forward.fill")
                        .font(.system(size: 30, weight: .bold))
                    Text(display.isLast ? "Finish" : "Next")
                        .font(Typo.display(20))
                }
                .foregroundColor(display.isPaused ? .white : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(display.isPaused ? Color.white.opacity(0.14) : Palette.spotlight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(StageZoneStyle())
            .accessibilityLabel(display.isLast ? "Finish run" : "Next segment")
            .accessibilityHint(display.isLast ? "" : "Closes this segment and starts \(display.nextTitle ?? "the next one")")
        }
        .disabled(isPreview)
    }
}

private struct StageZoneStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Shown when Next is tapped on the last segment. The clock is already frozen at the tap.
private struct FinishCard: View {
    let display: StageDisplay
    let skipping: Bool
    let onFinish: () -> Void
    let onKeepGoing: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Label(skipping ? "Skip & finish?" : "Finish rehearsal?", systemImage: "flag.checkered")
                    .font(Typo.title)
                    .foregroundColor(Palette.ink)
                Text(skipping
                     ? "“\(display.title)” will be marked Skipped and the run completes."
                     : "“\(display.title)” closes at \(TimeFormat.clock(display.elapsed)) — the moment you tapped.")
                    .font(Typo.callout)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    StatTile(label: "Total active", value: TimeFormat.clock(display.totalActive))
                    StatTile(label: "Markers", value: "\(display.markerCount)")
                }
                Button(skipping ? "Skip & Review" : "Finish & Review", action: onFinish)
                    .buttonStyle(.cuePrimary)
                Button("Keep Going", action: onKeepGoing)
                    .buttonStyle(.cueSecondary)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.paper))
            .padding(24)
            .frame(maxWidth: 480)
        }
        .environment(\.colorScheme, .light)
    }
}

/// Static stage preview (from Rehearsal Setup and Settings). Nothing runs and nothing is saved.
struct StagePreviewSheet: View {
    let container: AppContainer
    let versionID: UUID?
    let onClose: () -> Void

    var body: some View {
        let version = versionID.flatMap { container.scripts.version(id: $0) }
        let segments = version?.segments ?? []
        var display = StageDisplay.sample(from: segments.first)
        if let version {
            display.performanceName = version.displayName
            display.total = segments.count
            display.plannedTotal = version.plannedTotalSeconds
            display.nextTitle = segments.dropFirst().first?.title
            display.isLast = segments.count <= 1
        }
        return ZStack(alignment: .top) {
            StageBackdrop()
            StageLayout(display: display, scale: container.settings.stageTextSize.scale, actions: .inert, isPreview: true)
                .padding(.top, 44)
            HStack {
                Text("Stage Preview · \(container.settings.stageTextSize.title) text")
                    .font(Typo.captionBold)
                    .foregroundColor(Palette.onBlueMuted)
                Spacer()
                Button("Close", action: onClose)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Palette.spotlight)
                    .frame(minWidth: Metrics.minTap, minHeight: Metrics.minTap)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }
}
