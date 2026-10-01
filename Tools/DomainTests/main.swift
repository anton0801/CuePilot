import Foundation

// Standalone checks for the Domain layer. Run: Tools/DomainTests/run.sh
var failures = 0
var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() { passed += 1 } else { failures += 1; print("✘ line \(line): \(message)") }
}

final class FakeClock {
    var uptime: TimeInterval = 1000
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { uptime += seconds; date = date.addingTimeInterval(seconds) }
}

func makeWorld() -> (InMemoryDataStore, PerformanceUseCases, ScriptUseCases, RehearsalUseCases, FakeClock) {
    let clock = FakeClock()
    let store = InMemoryDataStore()
    return (store,
            PerformanceUseCases(store: store, clock: { clock.date }),
            ScriptUseCases(store: store, clock: { clock.date }),
            RehearsalUseCases(store: store, clock: { clock.date }),
            clock)
}

func seg(_ title: String, _ seconds: Int, optional: Bool = false) -> Segment {
    Segment(id: UUID(), title: title, plannedSeconds: seconds, cueText: "cue \(title)", detailedNotes: "", isOptional: optional)
}

// MARK: Drafts & publishing
do {
    let (store, perf, scripts, _, _) = makeWorld()
    check(ValidationRules.performanceName("") != nil, "empty name rejected")
    check(ValidationRules.performanceName(String(repeating: "a", count: 81)) != nil, "81 chars rejected")
    check(ValidationRules.performanceName(String(repeating: "a", count: 80)) == nil, "80 chars ok")
    let p = try perf.create(name: "  Talk  ", type: .talk, targetTotalSeconds: 600, versionLabel: "", generalNote: "")
    check(p.name == "Talk", "name trimmed")
    check(scripts.draft(performanceID: p.id)?.number == 1, "draft v1 created")
    check(!scripts.publishIssues(performanceID: p.id).isEmpty, "empty draft not publishable")
    var bad = seg("", 5)
    check(ValidationRules.segment(bad).count == 2, "title + planned range issues")
    bad.plannedSeconds = 3601
    check(!ValidationRules.segment(bad).isEmpty, "3601 s rejected")
    let a = seg("Intro", 60), b = seg("Story", 120), c = seg("Close", 30, optional: true)
    for s in [a, b, c] { try scripts.saveSegment(s, performanceID: p.id) }
    let v1 = try scripts.publishDraft(performanceID: p.id, changeNote: "first")
    check(v1.isPublished && v1.number == 1, "v1 published")
    check(scripts.draft(performanceID: p.id) == nil, "no draft after publish")
    check(perf.performance(id: p.id)?.currentVersionID == v1.id, "v1 current")
    // Editing a published version opens a new draft with the same segment IDs.
    var edited = b; edited.plannedSeconds = 90
    try scripts.saveSegment(edited, performanceID: p.id)
    let d2 = scripts.draft(performanceID: p.id)!
    check(d2.number == 2 && d2.basedOnVersionID == v1.id, "draft v2 based on v1")
    check(d2.segments.map(\.id) == [a.id, b.id, c.id], "stable IDs")
    check(scripts.version(id: v1.id)!.segment(withID: b.id)!.plannedSeconds == 120, "v1 untouched")
    try scripts.deleteSegment(id: c.id, performanceID: p.id)
    check(scripts.version(id: v1.id)!.segments.count == 3, "delete from draft keeps v1")
    // Total > 4h blocks publishing
    for i in 0..<5 { try scripts.saveSegment(seg("Long \(i)", 3600), performanceID: p.id) }
    check(scripts.publishIssues(performanceID: p.id).contains { $0.message.contains("4:00:00") }, "4h limit")
    try scripts.discardDraft(performanceID: p.id)
    check(scripts.draft(performanceID: p.id) == nil, "draft discarded")
    // Duplicate copies structure only
    let copy = try perf.duplicateStructure(id: p.id)
    let copyDraft = scripts.draft(performanceID: copy.id)!
    check(copyDraft.segments.count == 3 && copyDraft.segments[0].id != a.id, "duplicate copies segments with new IDs")
    check(store.database.runs.isEmpty, "no runs copied")
} catch { failures += 1; print("✘ drafts threw \(error)") }

// MARK: Engine timing
func startedRun(mode: RunMode, segments: [Segment], includeOptional: Bool = true, start: UUID? = nil)
    throws -> (RehearsalEngine, RehearsalUseCases, FakeClock, InMemoryDataStore) {
    let (store, perf, scripts, rehearsals, clock) = makeWorld()
    let p = try perf.create(name: "Set", type: .comedy, targetTotalSeconds: nil, versionLabel: "", generalNote: "")
    for s in segments { try scripts.saveSegment(s, performanceID: p.id) }
    let v = try scripts.publishDraft(performanceID: p.id, changeNote: "")
    let run = try rehearsals.start(RehearsalConfig(performanceID: p.id, versionID: v.id, mode: mode, startSegmentID: start, includeOptional: includeOptional))
    return (RehearsalEngine(run: run, now: { clock.uptime }, wallClock: { clock.date }), rehearsals, clock, store)
}

do {
    let s = [seg("A", 60), seg("B", 60), seg("C", 60)]
    let (engine, rehearsals, clock, _) = try startedRun(mode: .manual, segments: s)
    check((try? rehearsals.start(RehearsalConfig(performanceID: engine.run.performanceID, versionID: engine.run.versionID, mode: .manual, startSegmentID: nil, includeOptional: true))) == nil, "only one live run")
    clock.advance(30)
    engine.pause(); clock.advance(100); engine.resume()
    clock.advance(40)
    check(abs(engine.segmentElapsed - 70) < 0.001, "pause excluded from segment time (\(engine.segmentElapsed))")
    check(abs(engine.totalPaused - 100) < 0.001, "pause counted separately")
    check(engine.next(from: 0), "next closes A")
    check(!engine.next(from: 0), "second tap on same segment ignored")
    check(engine.run.records[0].status == .completed && abs(engine.run.records[0].activeSeconds - 70) < 0.001, "A = 70s")
    clock.advance(75) // B over plan — manual never auto-switches
    engine.tick()
    check(engine.currentIndex == 1, "manual overrun does not advance")
    // Background: no invented time
    engine.suspendForBackground(); clock.advance(3600); engine.returnToForeground()
    check(abs(engine.segmentElapsed - 75) < 0.001, "no background time")
    check(engine.isPaused, "return requires resume")
    clock.advance(10)
    check(abs(engine.totalPaused - 110) < 0.001, "foreground pause after return counted, background not (\(engine.totalPaused))")
    engine.resume()
    check(engine.next(from: 1), "B closed")
    check(engine.isOnLastSegment, "C last")
    check(!engine.next(from: 2), "next on last routes through finish")
    clock.advance(20)
    check(engine.finish(.completeCurrent, from: 2), "finish")
    check(engine.run.outcome == .completed && !engine.run.isPartial, "completed")
    let total = engine.run.records.reduce(0) { $0 + $1.activeSeconds }
    check(abs(total - engine.run.totalActiveSeconds) < 0.001, "segment sum == total active")
    try rehearsals.save(engine.run)
    let review = RunReview.build(run: rehearsals.run(id: engine.run.id)!, markers: [])
    check(review.completed.map(\.deviation) == [10, 15, -40], "deviation = actual − planned \(review.completed.map(\.deviation))")
    check(review.manualDeviationTotal == -15, "total deviation")
    check(review.largestOverrun?.segment.title == "B", "largest overrun")
} catch { failures += 1; print("✘ engine threw \(error)") }

do {
    // Auto advance with overflow carry and auto completion.
    let s = [seg("A", 10), seg("B", 20), seg("C", 10)]
    let (engine, _, clock, _) = try startedRun(mode: .autoAdvance, segments: s)
    clock.advance(35) // A(10) + B(20) + 5 into C
    engine.tick()
    check(engine.currentIndex == 2 && abs(engine.segmentElapsed - 5) < 0.001, "overflow carried into C")
    check(engine.run.records[0].advancedBy == .autoSchedule && engine.run.records[1].activeSeconds == 20, "closed on schedule")
    clock.advance(30)
    engine.tick()
    check(engine.run.outcome == .completed, "auto completes")
    check(abs(engine.run.totalActiveSeconds - 40) < 0.001, "total capped at schedule (\(engine.run.totalActiveSeconds))")
} catch { failures += 1; print("✘ auto threw \(error)") }

do {
    // Optional excluded, start segment → partial, skip, end early.
    let s = [seg("A", 60), seg("B", 60, optional: true), seg("C", 60), seg("D", 60), seg("E", 60)]
    let (engine, rehearsals, clock, _) = try startedRun(mode: .manual, segments: s, includeOptional: false, start: s[2].id)
    check(engine.run.records.map(\.status) == [.beforeStart, .excluded, .current, .pending, .pending], "initial statuses")
    check(engine.run.isPartial, "partial because of start segment")
    check(engine.position.current == 1 && engine.position.total == 3, "position among included")
    clock.advance(5)
    let marker = engine.markerPosition()!
    let m = try rehearsals.addMarker(runID: engine.run.id, segmentID: marker.segmentID, segmentOffset: marker.segmentOffset, totalOffset: marker.totalOffset)
    check(m.segmentID == s[2].id && abs(m.segmentOffsetSeconds - 5) < 0.001, "marker at snapshot time")
    check(!engine.skipOptional(from: 2), "cannot skip non-optional")
    engine.next(from: 2)
    clock.advance(12)
    engine.endEarly()
    check(engine.run.records.map(\.status) == [.beforeStart, .excluded, .completed, .unfinished, .notReached], "end early statuses")
    check(engine.run.outcome == .endedEarly, "ended early")
    try rehearsals.deleteMarker(id: m.id)
    check(abs(engine.run.totalActiveSeconds - 17) < 0.001, "deleting marker doesn't change timer")
} catch { failures += 1; print("✘ optional threw \(error)") }

do {
    // Crash recovery: saved as running → restored paused as interrupted, no gap time.
    let s = [seg("A", 60), seg("B", 60)]
    let (engine, rehearsals, clock, _) = try startedRun(mode: .manual, segments: s)
    clock.advance(20)
    try rehearsals.save(engine.checkpoint())
    clock.advance(40) // lost time after last checkpoint (app killed)
    let recovered = rehearsals.recoverInterruptedRun()
    check(recovered?.phase == .paused && recovered?.interruptionCount == 1, "recovered as paused/interrupted")
    check(abs((recovered?.totalActiveSeconds ?? 0) - 20) < 0.001, "restored at last checkpoint")
    check(rehearsals.recoverInterruptedRun() == nil, "recovery only once")
    try rehearsals.endLiveRun()
    check(rehearsals.run(id: engine.run.id)?.outcome == .interrupted, "ended after interruption → Interrupted")
    // A finished run can't be overwritten back to live.
    var tampered = rehearsals.run(id: engine.run.id)!
    tampered.outcome = .completed
    try rehearsals.save(tampered)
    check(rehearsals.run(id: engine.run.id)?.outcome == .interrupted, "finished result is final")
} catch { failures += 1; print("✘ recovery threw \(error)") }

// MARK: Comparison
do {
    let (_, perf, scripts, rehearsals, clock) = makeWorld()
    let p = try perf.create(name: "Toast", type: .other, targetTotalSeconds: nil, versionLabel: "", generalNote: "")
    let a = seg("Hello", 30), b = seg("Story", 60), c = seg("Cheers", 20)
    for s in [a, b, c] { try scripts.saveSegment(s, performanceID: p.id) }
    let v1 = try scripts.publishDraft(performanceID: p.id, changeNote: "")
    func run(_ mode: RunMode, _ durations: [TimeInterval], endEarlyAfter: Int? = nil) throws -> RehearsalRun {
        let r = try rehearsals.start(RehearsalConfig(performanceID: p.id, versionID: scripts.currentPublished(performanceID: p.id)!.id, mode: mode, startSegmentID: nil, includeOptional: true))
        let e = RehearsalEngine(run: r, now: { clock.uptime }, wallClock: { clock.date })
        for (i, d) in durations.enumerated() {
            clock.advance(d)
            if let stop = endEarlyAfter, i == stop { e.endEarly(); break }
            if e.isOnLastSegment { e.finish(.completeCurrent, from: e.currentIndex!) } else { e.next(from: e.currentIndex!) }
        }
        try rehearsals.save(e.run)
        return rehearsals.run(id: r.id)!
    }
    let r1 = try run(.manual, [35, 70, 20])
    let r2 = try run(.manual, [30, 90, 20], endEarlyAfter: 2)
    let auto = try run(.autoAdvance, [5, 5, 5])
    check(RunComparison.eligibility(r1, auto) != .ok && RunComparison.eligibility(r1, auto) != .warningDifferentVersions, "manual vs auto blocked")
    check(RunComparison.eligibility(r1, r2) == .ok, "same version ok")
    let cmp = RunComparison.build(a: r1, b: r2, markersA: [], markersB: [])
    check(cmp.rows.map { $0.difference } == [-5, 20, nil], "diffs; unfinished not counted \(cmp.rows.map { $0.difference })")
    check(cmp.totalDifference == 15, "total over counted rows")
    check(cmp.biggestGrowth?.title == "Story", "biggest growth")
    let pair = RunComparison.defaultPair(from: rehearsals.runs(performanceID: p.id), preferredVersionID: v1.id)
    check(pair?.a.id == r1.id && pair?.b.id == r2.id, "default pair = two manual runs of same version")
    // New version: change B's plan, delete C, add D
    var b2 = b; b2.plannedSeconds = 45
    try scripts.saveSegment(b2, performanceID: p.id)
    try scripts.deleteSegment(id: c.id, performanceID: p.id)
    let d = seg("Encore", 15)
    try scripts.saveSegment(d, performanceID: p.id)
    try scripts.moveSegments(performanceID: p.id, fromOffsets: IndexSet(integer: 2), toOffset: 0)
    _ = try scripts.publishDraft(performanceID: p.id, changeNote: "tighter")
    let r3 = try run(.manual, [10, 25, 50])
    check(RunComparison.eligibility(r1, r3) == .warningDifferentVersions, "different versions → warning")
    let cmp2 = RunComparison.build(a: r1, b: r3, markersA: [], markersB: [])
    check(cmp2.rows.map(\.title) == ["Hello", "Story"], "matched by ID not position \(cmp2.rows.map(\.title))")
    check(cmp2.rows[1].isChanged && cmp2.rows[0].isChanged == false, "changed plan marked")
    check(cmp2.onlyInA.map(\.segment.title) == ["Cheers"] && cmp2.onlyInB.map(\.segment.title) == ["Encore"], "unmatched separated")
    check(r1.snapshot.segments.count == 3, "old run keeps its snapshot")
} catch { failures += 1; print("✘ comparison threw \(error)") }

// MARK: Backup validation
do {
    let (store, perf, scripts, rehearsals, _) = makeWorld()
    let p = try perf.create(name: "Reading", type: .reading, targetTotalSeconds: nil, versionLabel: "", generalNote: "")
    try scripts.saveSegment(seg("Poem", 60), performanceID: p.id)
    let v = try scripts.publishDraft(performanceID: p.id, changeNote: "")
    let r = try rehearsals.start(RehearsalConfig(performanceID: p.id, versionID: v.id, mode: .manual, startSegmentID: nil, includeOptional: true))
    _ = try rehearsals.addMarker(runID: r.id, segmentID: v.segments[0].id, segmentOffset: 1, totalOffset: 1)
    check(BackupValidator.problems(in: store.database).isEmpty, "valid db has no problems")
    var broken = store.database
    broken.markers[0] = RunMarker(id: UUID(), runID: UUID(), segmentID: UUID(), segmentOffsetSeconds: 0, totalOffsetSeconds: 0, type: .review, note: "", createdAt: Date(), updatedAt: Date())
    broken.versions.append(ScriptVersion(id: UUID(), performanceID: UUID(), number: 9, label: "", generalNote: "", changeNote: "", status: .published, segments: [], createdAt: Date(), updatedAt: Date(), publishedAt: Date(), basedOnVersionID: nil))
    let problems = BackupValidator.problems(in: broken)
    check(problems.contains { $0.contains("marker") } && problems.contains { $0.contains("missing performance") }, "broken links reported \(problems)")
    let files = MemoryFiles()
    let backups = BackupUseCases(store: store, files: files, appVersion: "1.0")
    check(!backups.canReplace, "replace blocked while a run is live")
    check((try? backups.replace(with: .empty)) == nil && store.database.runs.count == 1, "blocked replace changes nothing")
    try rehearsals.endLiveRun()
    let data = try BackupUseCases.encoder().encode(BackupEnvelope(exportedAt: Date(), appVersion: "1", database: store.database))
    let inspection = backups.inspect(data: data)
    check(inspection.isValid && inspection.preview?.runs == 1, "round trip backup")
    check(!backups.inspect(data: Data("nope".utf8)).isValid, "garbage rejected")
    _ = try backups.replace(with: .empty)
    check(files.safety == 1 && store.database.isEmpty, "safety copy then replace")
    check((try? backups.deleteAllData(confirmation: "delete")) == nil, "DELETE must be exact")
} catch { failures += 1; print("✘ backup threw \(error)") }

final class MemoryFiles: FileExporting {
    var safety = 0
    func write(data: Data, fileName: String) throws -> URL { URL(fileURLWithPath: "/tmp/\(fileName)") }
    func writeSafetyBackup(data: Data, fileName: String) throws -> URL { safety += 1; return URL(fileURLWithPath: "/tmp/\(fileName)") }
}

// MARK: Insights — trim hint and segment history
do {
    let (store, perf, scripts, rehearsals, clock) = makeWorld()
    let p = try perf.create(name: "Keynote", type: .talk, targetTotalSeconds: 200, versionLabel: "", generalNote: "")
    let a = seg("Hook", 60), b = seg("Demo", 90), c = seg("Extra", 30, optional: true), d = seg("Close", 30)
    for s in [a, b, c, d] { try scripts.saveSegment(s, performanceID: p.id) }
    let v1 = try scripts.publishDraft(performanceID: p.id, changeNote: "")
    let insights = InsightsUseCases(store: store)
    func manualRun(_ durations: [TimeInterval], skipIndex: Int? = nil, endEarlyAt: Int? = nil, start: UUID? = nil, mode: RunMode = .manual) throws -> RehearsalRun {
        clock.advance(3600)
        let r = try rehearsals.start(RehearsalConfig(performanceID: p.id, versionID: v1.id, mode: mode, startSegmentID: start, includeOptional: true))
        let e = RehearsalEngine(run: r, now: { clock.uptime }, wallClock: { clock.date })
        for (i, t) in durations.enumerated() {
            guard let index = e.currentIndex else { break }
            clock.advance(t)
            if endEarlyAt == i { e.endEarly(); break }
            if skipIndex == i { e.skipOptional(from: index); continue }
            if e.isOnLastSegment { e.finish(.completeCurrent, from: index) } else { e.next(from: index) }
        }
        if mode == .autoAdvance { while !e.isFinished { clock.advance(1); e.tick() } }
        try rehearsals.save(e.run)
        return rehearsals.run(id: r.id)!
    }
    let r1 = try manualRun([70, 100, 5, 40], skipIndex: 2)          // Extra skipped
    guard case let .success(hint)? = insights.trimHint(runID: r1.id) else { throw DomainError.notFound("hint") }
    check(hint.actualTotal == 210 && hint.gap == 10 && hint.isOver, "total 210 vs target 200 → +10 (\(hint.actualTotal), \(hint.gap))")
    check(hint.overruns.map(\.title) == ["Demo", "Hook", "Close"] && hint.overruns.map(\.over) == [10, 10, 10] || hint.overruns.count == 3, "all overruns listed")
    check(hint.topSavings == 30 && hint.remainingAfterTop == 0, "top savings close the gap")
    check(hint.skippedOptionalTitles == ["Extra"], "skipped optional noted")
    check(hint.planOverTarget == 10, "plan 210 itself is over target 200 by 10")
    let early = try manualRun([60, 90], endEarlyAt: 1)
    check(insights.trimHint(runID: early.id).map { if case .failure(.notCompleted) = $0 { return true } else { return false } } == true, "ended early not eligible")
    let partial = try manualRun([90, 30, 30], start: b.id)
    check(insights.trimHint(runID: partial.id).map { if case .failure(.partialStart) = $0 { return true } else { return false } } == true, "partial start not eligible")
    let auto = try manualRun([], mode: .autoAdvance)
    check(insights.trimHint(runID: auto.id).map { if case .failure(.autoAdvance) = $0 { return true } else { return false } } == true, "auto not eligible")
    check(insights.latestTrimHint(performanceID: p.id)?.run.id == r1.id, "latest hint skips ineligible newer runs")
    // No target → reference is the plan of performed segments.
    try perf.updateDetails(id: p.id, name: "Keynote", type: .talk, targetTotalSeconds: nil)
    let noTarget = insights.latestTrimHint(performanceID: p.id)!
    check(noTarget.reference == .plan(180) && noTarget.gap == 30, "plan reference excludes skipped optional (\(noTarget.reference))")

    // History: Demo grows 100 → 104 → 112 → 125; Hook shrinks; Close steady; Extra mostly skipped.
    _ = try manualRun([66, 104, 30, 31])
    _ = try manualRun([63, 112, 30, 30])
    _ = try manualRun([58, 125, 5, 31], skipIndex: 2)
    let history = insights.history(performanceID: p.id, limit: 10)!
    func trend(_ title: String) -> SegmentTrend? { history.segments.first { $0.segment.title == title }?.trend }
    check(history.runs.count == 6 && history.runs.allSatisfy { $0.mode == .manual }, "manual runs only, auto excluded (\(history.runs.count))")
    check(trend("Demo") == .growing, "Demo growing (\(String(describing: trend("Demo"))))")
    check(trend("Hook") == .shrinking, "Hook shrinking")
    check(trend("Close") == .steady, "Close steady")
    let demo = history.segments.first { $0.segment.title == "Demo" }!
    check(demo.points.count == 6 && demo.points.map(\.actual).contains(nil), "aligned slots; unfinished run's gap is nil, not zero")
    let hook = history.segments.first { $0.segment.title == "Hook" }!
    check(hook.points.contains { $0.status == .beforeStart && $0.actual == nil }, "partial-start run leaves a gap")
    check(demo.change == 25, "change first→last counted (\(String(describing: demo.change)))")
    let extra = history.segments.first { $0.segment.title == "Extra" }!
    check(extra.points.filter { $0.status == .skipped }.allSatisfy { $0.actual == nil }, "skipped is a gap")
    check(insights.history(performanceID: p.id, limit: 2)?.runs.count == 2, "window limit")
    check(PerformanceHistory.trend(of: [60, 61, 62]) != .growing, "1 s steps are noise")
} catch { failures += 1; print("✘ insights threw \(error)") }

check(TimeFormat.clock(3725) == "1:02:05" && TimeFormat.clock(65) == "1:05" && TimeFormat.delta(-5) == "−0:05", "formatting")

print(failures == 0 ? "✔ all \(passed) checks passed" : "✘ \(failures) failed, \(passed) passed")
exit(failures == 0 ? 0 : 1)
