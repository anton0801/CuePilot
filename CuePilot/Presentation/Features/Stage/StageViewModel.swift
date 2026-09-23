import Combine
import UIKit

/// Everything Stage Mode shows, in whole seconds so the view only redraws when a digit changes.
struct StageDisplay: Equatable {
    var index: Int
    var performanceName: String
    var versionName: String
    var mode: RunMode
    var position: Int
    var total: Int
    var title: String
    var cue: String
    var isOptional: Bool
    var elapsed: Int
    var planned: Int
    var totalActive: Int
    var plannedTotal: Int
    var totalPaused: Int
    var nextTitle: String?
    var isPaused: Bool
    var isLast: Bool
    var markerCount: Int

    var remaining: Int { planned - elapsed }
    var isExceeded: Bool { elapsed > planned }
    var progress: Double { min(1, Double(elapsed) / Double(max(planned, 1))) }

    static func sample(from segment: Segment?, mode: RunMode = .manual) -> StageDisplay {
        StageDisplay(
            index: 0, performanceName: "Preview", versionName: "", mode: mode, position: 1, total: 1,
            title: segment?.title ?? "Opening", cue: segment?.cueText ?? "Start with the story about the broken umbrella.",
            isOptional: segment?.isOptional ?? false, elapsed: 0, planned: segment?.plannedSeconds ?? 90,
            totalActive: 0, plannedTotal: segment?.plannedSeconds ?? 90, totalPaused: 0,
            nextTitle: "Next segment", isPaused: true, isLast: false, markerCount: 0
        )
    }
}

@MainActor
final class StageViewModel: ObservableObject {
    enum Exit: Equatable {
        case leave
        case review(UUID)
    }

    @Published private(set) var display: StageDisplay?
    @Published private(set) var missingRun = false
    @Published var showEndDialog = false
    @Published private(set) var pendingFinish: RehearsalEngine.PendingFinish?
    @Published var showMarkers = false
    @Published private(set) var toast: String?
    @Published var alert: AlertMessage?
    @Published var showInterruptedNotice = false
    @Published var showAwayNotice = false
    @Published private(set) var exit: Exit?

    let runID: UUID
    private let container: AppContainer
    private var engine: RehearsalEngine?
    private var timer: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var lastCheckpoint: TimeInterval = 0
    private var wasRunningBeforeDialog = false
    private var isForeground = true
    private var markerCount = 0
    private var toastTask: Task<Void, Never>?
    private var reportedSaveError = false
    private var keepAwake = true

    private static func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(container: AppContainer, runID: UUID) {
        self.container = container
        self.runID = runID
        guard let run = container.rehearsals.run(id: runID), run.isLive else {
            missingRun = true
            return
        }
        engine = RehearsalEngine(run: run, now: Self.uptime)
        showInterruptedNotice = run.interruptionCount > 0
        markerCount = container.rehearsals.markers(runID: runID).count
        lastCheckpoint = Self.uptime()
        refresh()

        container.databaseChanges
            .map { db in db.markers.filter { $0.runID == runID }.count }
            .removeDuplicates()
            .sink { [weak self] count in
                self?.markerCount = count
                self?.refresh()
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.appWillResignActive() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.appDidBecomeActive() }
            .store(in: &cancellables)
    }

    var isPaused: Bool { engine?.isPaused ?? true }
    var interruptionCount: Int { engine?.run.interruptionCount ?? 0 }
    var liveRun: RehearsalRun? { engine?.run }

    // MARK: Lifecycle

    func onAppear(keepScreenAwake: Bool) {
        keepAwake = keepScreenAwake
        timer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        updateScreenAwake()
    }

    func onDisappear() {
        timer?.cancel()
        timer = nil
        ScreenAwake.set(false)
        // Leaving the stage never leaves the clock running unattended.
        if let engine, !engine.isFinished, engine.isRunning {
            engine.pause()
            persist()
        }
    }

    private func appWillResignActive() {
        guard let engine, !engine.isFinished, isForeground else { return }
        isForeground = false
        let wasRunning = engine.isRunning
        engine.suspendForBackground()
        persist()
        ScreenAwake.set(false)
        if wasRunning { showAwayNotice = true }
        refresh()
    }

    private func appDidBecomeActive() {
        guard let engine, !engine.isFinished, !isForeground else { return }
        isForeground = true
        engine.returnToForeground()
        updateScreenAwake()
        refresh()
    }

    private func updateScreenAwake() {
        // Only while this run is on screen and the app is in the foreground.
        ScreenAwake.set(keepAwake && isForeground && engine?.isFinished == false)
    }

    private func tick() {
        guard let engine, !engine.isFinished else { return }
        if engine.tick() {
            Haptics.light()
            persist()
            if engine.isFinished {
                finishExit()
                return
            }
        }
        if Self.uptime() - lastCheckpoint >= 5 {
            persist()
        }
        refresh()
    }

    private func refresh() {
        guard let engine, let index = engine.currentIndex, let segment = engine.currentSegment else { return }
        let position = engine.position
        let next = StageDisplay(
            index: index,
            performanceName: engine.run.snapshot.performanceName,
            versionName: engine.run.snapshot.versionDisplayName,
            mode: engine.run.mode,
            position: position.current,
            total: position.total,
            title: segment.title,
            cue: segment.cueText,
            isOptional: segment.isOptional,
            elapsed: Int(engine.segmentElapsed.rounded(.down)),
            planned: segment.plannedSeconds,
            totalActive: Int(engine.totalActive.rounded(.down)),
            plannedTotal: engine.plannedIncludedTotal,
            totalPaused: Int(engine.totalPaused.rounded(.down)),
            nextTitle: engine.nextSegment?.title,
            isPaused: engine.isPaused,
            isLast: engine.isOnLastSegment,
            markerCount: markerCount
        )
        if next != display { display = next }
    }

    private func persist() {
        guard let engine else { return }
        lastCheckpoint = Self.uptime()
        do {
            try container.rehearsals.save(engine.checkpoint())
        } catch {
            if !reportedSaveError {
                reportedSaveError = true
                alert = AlertMessage(title: "Couldn't save the run", error)
            }
        }
    }

    // MARK: Actions

    func togglePause() {
        guard let engine, !engine.isFinished else { return }
        if engine.isRunning {
            engine.pause()
        } else {
            engine.resume()
            showAwayNotice = false
            showInterruptedNotice = false
        }
        Haptics.tap()
        persist()
        refresh()
    }

    func next(displayedIndex: Int) {
        guard let engine, !engine.isFinished, engine.currentIndex == displayedIndex else { return }
        if engine.isOnLastSegment {
            requestFinish(.completeCurrent)
            return
        }
        if engine.next(from: displayedIndex) {
            Haptics.tap()
            persist()
            refresh()
        }
    }

    func skipOptional(displayedIndex: Int) {
        guard let engine, !engine.isFinished, engine.currentIndex == displayedIndex,
              engine.currentSegment?.isOptional == true else { return }
        if engine.isOnLastSegment {
            requestFinish(.skipCurrent)
            return
        }
        if engine.skipOptional(from: displayedIndex) {
            Haptics.tap()
            persist()
            refresh()
        }
    }

    /// Next on the last segment: freeze the clock at the tap and ask to finish.
    private func requestFinish(_ action: RehearsalEngine.PendingFinish) {
        guard let engine else { return }
        wasRunningBeforeDialog = engine.isRunning
        engine.pause()
        persist()
        refresh()
        pendingFinish = action
    }

    func confirmFinish() {
        guard let engine, let action = pendingFinish, let index = engine.currentIndex else { return }
        pendingFinish = nil
        if engine.finish(action, from: index) {
            Haptics.success()
            persist()
            finishExit()
        }
    }

    func keepGoing() {
        pendingFinish = nil
        resumeIfNeededAfterDialog()
    }

    func requestEnd() {
        guard let engine, !engine.isFinished else { return }
        wasRunningBeforeDialog = engine.isRunning
        engine.pause()
        persist()
        refresh()
        showEndDialog = true
    }

    func endEarly() {
        guard let engine, !engine.isFinished else { return }
        engine.endEarly(as: engine.run.interruptionCount > 0 ? .interrupted : .endedEarly)
        persist()
        finishExit()
    }

    func finishFromEndDialog() {
        guard let engine, engine.isOnLastSegment else { return }
        pendingFinish = .completeCurrent
        confirmFinish()
    }

    func continueAfterEnd() {
        resumeIfNeededAfterDialog()
    }

    private func resumeIfNeededAfterDialog() {
        guard let engine, !engine.isFinished else { return }
        if wasRunningBeforeDialog, isForeground {
            engine.resume()
            persist()
        }
        wasRunningBeforeDialog = false
        refresh()
    }

    func addMarker() {
        guard let engine, !engine.isFinished, let position = engine.markerPosition() else { return }
        do {
            try container.rehearsals.addMarker(runID: runID, segmentID: position.segmentID,
                                               segmentOffset: position.segmentOffset, totalOffset: position.totalOffset)
            Haptics.tap()
            showToast("Marker saved · \(TimeFormat.clock(position.segmentOffset)) into “\(engine.currentSegment?.title ?? "")”")
        } catch {
            alert = AlertMessage(error)
        }
    }

    /// The marker editor opens only while paused.
    func openMarkers() {
        guard engine?.isPaused == true else {
            showToast("Pause first to edit markers")
            return
        }
        showMarkers = true
    }

    func leaveStage() {
        if let engine, !engine.isFinished {
            if engine.isRunning { engine.pause() }
            persist()
        }
        exit = .leave
    }

    private func finishExit() {
        ScreenAwake.set(false)
        timer?.cancel()
        exit = .review(runID)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
