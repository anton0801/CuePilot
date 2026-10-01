import Foundation

/// Pure timing state machine for one live run.
///
/// Time is always derived from a monotonic clock (`now`), never from counting ticks, so the UI refresh rate
/// has no influence on the measured durations. Accumulated values are folded into the run record on every
/// transition; between transitions only the "since" markers move.
final class RehearsalEngine {
    enum PendingFinish: Equatable {
        /// Close the last segment as completed.
        case completeCurrent
        /// Skip the last (optional) segment and finish.
        case skipCurrent
    }

    private(set) var run: RehearsalRun
    private let now: () -> TimeInterval
    private let wallClock: () -> Date

    /// Monotonic time when the current running stint began. `nil` while paused or finished.
    private var runningSince: TimeInterval?
    /// Monotonic time when the current foreground pause began. `nil` while running or while the app is away.
    private var pausedSince: TimeInterval?

    init(run: RehearsalRun, now: @escaping () -> TimeInterval, wallClock: @escaping () -> Date = Date.init) {
        self.run = run
        self.now = now
        self.wallClock = wallClock
        switch run.phase {
        case .running:
            runningSince = now()
        case .paused:
            pausedSince = now()
        case nil:
            break
        }
    }

    // MARK: - Read-outs

    var isFinished: Bool { run.outcome != nil }
    var isRunning: Bool { run.phase == .running }
    var isPaused: Bool { run.phase == .paused }

    var currentIndex: Int? { run.currentIndex }
    var currentSegment: Segment? { run.currentSegment }

    private var runningDelta: Double {
        guard let runningSince else { return 0 }
        return max(0, now() - runningSince)
    }

    private var pausedDelta: Double {
        guard let pausedSince else { return 0 }
        return max(0, now() - pausedSince)
    }

    var segmentElapsed: Double {
        guard let index = run.currentIndex else { return 0 }
        return run.records[index].activeSeconds + runningDelta
    }

    var totalActive: Double { run.totalActiveSeconds + runningDelta }
    var totalPaused: Double { run.totalPausedSeconds + pausedDelta }

    var nextIncludedIndex: Int? {
        guard let index = run.currentIndex else { return nil }
        return nextIndex(after: index)
    }

    var nextSegment: Segment? { nextIncludedIndex.map { run.snapshot.segments[$0] } }
    var isOnLastSegment: Bool { run.currentIndex != nil && nextIncludedIndex == nil }

    /// 1-based position among included segments, and their count.
    var position: (current: Int, total: Int) {
        let included = run.includedIndices
        guard let index = run.currentIndex, let pos = included.firstIndex(of: index) else {
            return (included.count, included.count)
        }
        return (pos + 1, included.count)
    }

    /// Planned seconds of the included segments from the start segment on.
    var plannedIncludedTotal: Int {
        run.includedIndices.reduce(0) { $0 + run.snapshot.segments[$1].plannedSeconds }
    }

    // MARK: - Transitions

    func pause() {
        guard run.phase == .running else { return }
        foldRunning()
        runningSince = nil
        pausedSince = now()
        run.phase = .paused
    }

    func resume() {
        guard run.phase == .paused else { return }
        foldPaused()
        pausedSince = nil
        runningSince = now()
        run.phase = .running
    }

    /// The app is leaving the screen: pause, and stop counting paused time while the app is away,
    /// so no time is invented for the background.
    func suspendForBackground() {
        pause()
        foldPaused()
        pausedSince = nil
    }

    /// Back on screen while paused: resume counting foreground pause time. The run stays paused.
    func returnToForeground() {
        guard run.phase == .paused, pausedSince == nil else { return }
        pausedSince = now()
    }

    /// Auto Advance: close every segment whose planned time has been reached. Returns true if anything changed.
    @discardableResult
    func tick() -> Bool {
        guard run.mode == .autoAdvance, run.phase == .running, let index = run.currentIndex else { return false }
        let planned = Double(run.snapshot.segments[index].plannedSeconds)
        guard segmentElapsed >= planned else { return false }

        foldRunning()
        runningSince = now()
        var changed = false
        while let current = run.currentIndex {
            let plan = Double(run.snapshot.segments[current].plannedSeconds)
            let spent = run.records[current].activeSeconds
            guard spent >= plan else { break }
            let overflow = spent - plan
            run.records[current].activeSeconds = plan
            run.records[current].status = .completed
            run.records[current].advancedBy = .autoSchedule
            changed = true
            if let next = nextIndex(after: current) {
                run.currentIndex = next
                run.records[next].status = .current
                run.records[next].activeSeconds += overflow
            } else {
                // The schedule ran out: the run completes exactly at the planned end.
                run.totalActiveSeconds = max(0, run.totalActiveSeconds - overflow)
                complete(outcome: .completed)
            }
        }
        return changed
    }

    /// Closes the displayed segment exactly once. Ignored if the stage already moved on
    /// (for example a double tap), or if the displayed segment is the last one — that goes through Finish.
    @discardableResult
    func next(from displayedIndex: Int) -> Bool {
        guard run.outcome == nil, run.currentIndex == displayedIndex, let next = nextIndex(after: displayedIndex) else {
            return false
        }
        foldAll()
        run.records[displayedIndex].status = .completed
        run.records[displayedIndex].advancedBy = .manualNext
        run.currentIndex = next
        run.records[next].status = .current
        return true
    }

    /// Skips the displayed optional segment. Its time so far stays recorded but never counts.
    @discardableResult
    func skipOptional(from displayedIndex: Int) -> Bool {
        guard run.outcome == nil,
              run.currentIndex == displayedIndex,
              run.snapshot.segments[displayedIndex].isOptional,
              let next = nextIndex(after: displayedIndex) else { return false }
        foldAll()
        run.records[displayedIndex].status = .skipped
        run.currentIndex = next
        run.records[next].status = .current
        return true
    }

    /// Finishes the run from the last segment.
    @discardableResult
    func finish(_ action: PendingFinish, from displayedIndex: Int) -> Bool {
        guard run.outcome == nil, run.currentIndex == displayedIndex, nextIndex(after: displayedIndex) == nil else {
            return false
        }
        foldAll()
        switch action {
        case .completeCurrent:
            run.records[displayedIndex].status = .completed
            run.records[displayedIndex].advancedBy = .finish
        case .skipCurrent:
            run.records[displayedIndex].status = .skipped
        }
        complete(outcome: .completed)
        return true
    }

    /// Ends before the script is done. The segment on stage is kept as unfinished, the rest as not reached.
    func endEarly(as outcome: RunOutcome = .endedEarly) {
        guard run.outcome == nil else { return }
        foldAll()
        if let index = run.currentIndex {
            run.records[index].status = .unfinished
        }
        for index in run.records.indices where run.records[index].status == .pending {
            run.records[index].status = .notReached
        }
        complete(outcome: outcome == .completed ? .endedEarly : outcome)
    }

    /// Where a marker dropped right now belongs.
    func markerPosition() -> (segmentID: UUID, segmentOffset: Double, totalOffset: Double)? {
        guard let segment = run.currentSegment else { return nil }
        return (segment.id, segmentElapsed, totalActive)
    }

    /// The run with all in-flight time folded in, ready to be saved as a checkpoint.
    /// The engine keeps ticking from the same instant, so saving never loses or duplicates time.
    func checkpoint() -> RehearsalRun {
        foldAll()
        if run.phase == .running { runningSince = now() }
        if pausedSince != nil { pausedSince = now() }
        run.lastCheckpointAt = wallClock()
        return run
    }

    // MARK: - Internals

    private func nextIndex(after index: Int) -> Int? {
        var candidate = index + 1
        while candidate < run.records.count {
            if run.records[candidate].status == .pending { return candidate }
            candidate += 1
        }
        return nil
    }

    private func foldRunning() {
        guard let since = runningSince else { return }
        let delta = max(0, now() - since)
        if let index = run.currentIndex {
            run.records[index].activeSeconds += delta
        }
        run.totalActiveSeconds += delta
        runningSince = now()
    }

    private func foldPaused() {
        guard let since = pausedSince else { return }
        let delta = max(0, now() - since)
        if let index = run.currentIndex {
            run.records[index].pausedSeconds += delta
        }
        run.totalPausedSeconds += delta
        pausedSince = now()
    }

    private func foldAll() {
        foldRunning()
        foldPaused()
    }

    private func complete(outcome: RunOutcome) {
        runningSince = nil
        pausedSince = nil
        run.currentIndex = nil
        run.phase = nil
        run.outcome = outcome
        let date = wallClock()
        run.endedAt = date
        run.lastCheckpointAt = date
    }
}

final class Booth: Vault {

    private let home = UserDefaults.standard
    private var box: UserDefaults? { UserDefaults(suiteName: Playbill.suite) }

    private var folder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CueStudio", isDirectory: true)
    }

    private var file: URL { folder.appendingPathComponent("cp_marquee_archive.json") }

    func load() -> Marquee {
        if let raw = try? Data(contentsOf: file),
           let plain = decode(raw),
           let archive = try? decoder.decode(Archive.self, from: plain) {
            return Marquee(archive)
        }
        return recall()
    }

    func save(_ marquee: Marquee) {
        let archive = marquee.stow()
        if let plain = try? encoder.encode(archive), let coded = encode(plain) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? coded.write(to: file, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(archive.consentLit, forKey: Marks.grant)
            store.set(archive.consentDimmed, forKey: Marks.deny)
            if let at = archive.consentMarkedAt {
                store.set(at.timeIntervalSince1970, forKey: Marks.stamp)
            }
        }
    }

    func brand(_ url: String) {
        home.set(url, forKey: Marks.route)
        box?.set("Active", forKey: Marks.mode)
    }

    func prime() {
        home.set(true, forKey: Marks.primed)
        box?.set(true, forKey: Marks.primed)
    }

    private func recall() -> Marquee {
        var marquee = Marquee()
        marquee.consentLit = (box?.bool(forKey: Marks.grant) ?? false) || home.bool(forKey: Marks.grant)
        marquee.consentDimmed = (box?.bool(forKey: Marks.deny) ?? false) || home.bool(forKey: Marks.deny)
        let ts = box?.double(forKey: Marks.stamp) ?? home.double(forKey: Marks.stamp)
        marquee.consentMarkedAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        marquee.routeURL = home.string(forKey: Marks.route)
        marquee.routeMode = box?.string(forKey: Marks.mode)
        marquee.cold = !home.bool(forKey: Marks.primed)
        return marquee
    }

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return dec
    }

    private func encode(_ data: Data) -> Data? {
        let swapped = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: Playbill.plus)
            .replacingOccurrences(of: "/", with: Playbill.slash)
        return swapped.data(using: .utf8)
    }

    private func decode(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let restored = text
            .replacingOccurrences(of: Playbill.plus, with: "+")
            .replacingOccurrences(of: Playbill.slash, with: "/")
        return Data(base64Encoded: restored)
    }
}
