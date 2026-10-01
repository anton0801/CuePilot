#if DEBUG
import Foundation

/// DEBUG-only: `-cpScenario <name>` launch argument opens a screen with sample data in an isolated
/// temporary store, for screenshots and manual QA. Never touches the real library; compiled out of Release.
@MainActor
enum DebugScenario {
    static var name: String? { UserDefaults.standard.string(forKey: "cpScenario") }

    private static var ids: (performance: UUID, segment: UUID, runA: UUID, runB: UUID, runV1: UUID, live: UUID?)?

    static func makeContainer() -> AppContainer? {
        guard let name else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cp-scenario", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let suite = "cp-scenario"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = UserDefaultsSettingsRepository(defaults: UserDefaults(suiteName: suite) ?? .standard)
        if name != "onboarding" {
            settings.update { $0.hasCompletedOnboarding = true }
        }
        let store = FileDatabaseStore(directory: directory)
        if name != "onboarding" && name != "empty" {
            seed(store: store, withLiveRun: ["stage", "stagepaused", "homelive"].contains(name))
        }
        let container = AppContainer(store: store, settingsRepository: settings)
        if name == "exportpdf" { writeSampleExports(container) }
        return container
    }

    /// Renders every export kind into Documents/debug-exports for inspection.
    private static func writeSampleExports(_ container: AppContainer) {
        guard let ids, let version = container.scripts.currentPublished(performanceID: ids.performance),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("debug-exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let all = ExportOptions(includeDetailedNotes: true, includeMarkers: true, includeReflection: true)
        let jobs: [(String, ExportSource)] = [
            ("cuesheet", .cueSheet(versionID: version.id)),
            ("summary", .runSummary(runID: ids.runB)),
            ("comparison", .comparison(runA: ids.runV1, runB: ids.runB))
        ]
        for (name, source) in jobs {
            if let data = try? container.exports.pdfData(for: source, options: all) {
                try? data.write(to: folder.appendingPathComponent("\(name).pdf"))
            }
            if let url = try? container.exports.exportCSV(for: source, options: all) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name).csv"))
                try? FileManager.default.copyItem(at: url, to: folder.appendingPathComponent("\(name).csv"))
            }
        }
    }

    static func navigate(_ navigator: AppNavigator) {
        guard let name, let ids else { return }
        switch name {
        case "library": navigator.open(.performances, routes: [.library(showArchived: false)])
        case "editor": navigator.open(.performances, routes: [.performanceEditor(ids.performance)])
        case "segment": navigator.open(.performances, routes: [.performanceEditor(ids.performance), .segmentEditor(performanceID: ids.performance, segmentID: ids.segment)])
        case "setup": navigator.open(.rehearse, routes: [])
        case "stage", "stagepaused": if let live = ids.live { navigator.presentStage(runID: live) }
        case "markers": navigator.open(.runs, routes: [.review(runID: ids.runB), .markers(runID: ids.runB)])
        case "runs": navigator.open(.runs, routes: [])
        case "review": navigator.open(.runs, routes: [.review(runID: ids.runB)])
        case "compare": navigator.open(.runs, routes: [.compare(ComparePreset(performanceID: ids.performance, runA: ids.runA, runB: ids.runB))])
        case "compareversions": navigator.open(.runs, routes: [.compare(ComparePreset(performanceID: ids.performance, runA: ids.runV1, runB: ids.runB))])
        case "versions": navigator.open(.performances, routes: [.versions(performanceID: ids.performance, highlight: nil)])
        case "history": navigator.open(.performances, routes: [.segmentHistory(performanceID: ids.performance)])
        case "export": navigator.open(.performances, routes: [.export(ExportPreset(kind: .runSummary, performanceID: ids.performance, runID: ids.runB))])
        case "settings": navigator.open(.performances, routes: [.settings])
        default: break
        }
    }

    // MARK: Seed

    private final class Clock {
        var date = Date().addingTimeInterval(-6 * 86_400)
        var uptime: TimeInterval = 10_000
        func advance(_ seconds: TimeInterval) {
            date = date.addingTimeInterval(seconds)
            uptime += seconds
        }
    }

    private static func seed(store: DataStore, withLiveRun: Bool) {
        let clock = Clock()
        let performances = PerformanceUseCases(store: store, clock: { clock.date })
        let scripts = ScriptUseCases(store: store, clock: { clock.date })
        let rehearsals = RehearsalUseCases(store: store, clock: { clock.date })

        func segment(_ title: String, _ seconds: Int, _ cue: String, optional: Bool = false) -> Segment {
            Segment(id: UUID(), title: title, plannedSeconds: seconds, cueText: cue, detailedNotes: "", isOptional: optional)
        }

        do {
            let performance = try performances.create(name: "Design Meetup Keynote", type: .talk, targetTotalSeconds: 11 * 60,
                                                      versionLabel: "First pass", generalNote: "Clicker in left pocket. Water on the stool.")
            let segments = [
                segment("Cold open", 60, "Start with the broken umbrella. Pause after the punchline."),
                segment("Why rehearsals drift", 180, "Three reasons, one slide each. Don't read the bullets."),
                segment("The segment method", 240, "Show the cue sheet: name, planned time, one short cue."),
                segment("Audience example", 120, "Only if the room is warm — ask for one volunteer.", optional: true),
                segment("Closing line", 45, "Back to the umbrella. Thank the organisers.")
            ]
            for item in segments { try scripts.saveSegment(item, performanceID: performance.id) }
            let v1 = try scripts.publishDraft(performanceID: performance.id, changeNote: "Initial structure")
            clock.advance(3600)

            func rehearse(_ version: ScriptVersion, durations: [TimeInterval], pause: TimeInterval = 0, markers: [(Int, TimeInterval, MarkerType, String)] = []) throws -> RehearsalRun {
                let run = try rehearsals.start(RehearsalConfig(performanceID: performance.id, versionID: version.id, mode: .manual,
                                                               startSegmentID: nil, includeOptional: true))
                let engine = RehearsalEngine(run: run, now: { clock.uptime }, wallClock: { clock.date })
                for (index, duration) in durations.enumerated() {
                    for marker in markers where marker.0 == index {
                        clock.advance(marker.1)
                        if let position = engine.markerPosition() {
                            let saved = try rehearsals.addMarker(runID: run.id, segmentID: position.segmentID,
                                                                 segmentOffset: position.segmentOffset, totalOffset: position.totalOffset, type: marker.2)
                            try rehearsals.updateMarker(id: saved.id, type: marker.2, note: marker.3)
                        }
                    }
                    let already = markers.filter { $0.0 == index }.reduce(0) { $0 + $1.1 }
                    clock.advance(duration - already)
                    if index == 1 && pause > 0 {
                        engine.pause()
                        clock.advance(pause)
                        engine.resume()
                    }
                    guard let current = engine.currentIndex else { break }
                    if engine.isOnLastSegment {
                        engine.finish(.completeCurrent, from: current)
                    } else {
                        engine.next(from: current)
                    }
                }
                try rehearsals.save(engine.run)
                clock.advance(86_400)
                return rehearsals.run(id: run.id) ?? engine.run
            }

            let runV1 = try rehearse(v1, durations: [72, 231, 262, 95, 50], pause: 40,
                                     markers: [(1, 140, .shorten, "Second reason repeats the first — merge them.")])
            try rehearsals.saveReflection(runID: runV1.id, text: "Middle section drags. Intro landed.")

            // v2: tighter middle, audience example dropped.
            var tighter = segments[1]
            tighter.plannedSeconds = 150
            tighter.cueText = "Two reasons. Merge the old second and third slides."
            try scripts.saveSegment(tighter, performanceID: performance.id)
            try scripts.deleteSegment(id: segments[3].id, performanceID: performance.id)
            try scripts.updateDraftDetails(performanceID: performance.id, label: "Tighter middle", generalNote: "Clicker in left pocket. Water on the stool.")
            let v2 = try scripts.publishDraft(performanceID: performance.id, changeNote: "Merged reasons, dropped the audience example")
            clock.advance(3600)

            let runA = try rehearse(v2, durations: [66, 171, 250, 48],
                                    markers: [(2, 120, .clarify, "Slide 7 needs a bigger example.")])
            let runB = try rehearse(v2, durations: [61, 158, 283, 44], pause: 25,
                                    markers: [(2, 200, .shorten, "Method demo runs long — cut the second example."),
                                              (2, 30, .review, "")])
            try rehearsals.saveReflection(runID: runB.id, text: "Better pace up front. The method demo keeps growing.")
            // A later run where the method demo grows again — gives Segment History a clear "Growing" trend.
            _ = try rehearse(v2, durations: [63, 152, 296, 46])

            // Second, archived performance for the Library.
            let toast = try performances.create(name: "Sister's Wedding Toast", type: .other, targetTotalSeconds: 180, versionLabel: "", generalNote: "")
            try scripts.saveSegment(segment("Hello & thanks", 30, "Thank the parents first."), performanceID: toast.id)
            try scripts.saveSegment(segment("The camping story", 90, "Tent, rain, the lost shoe."), performanceID: toast.id)
            try scripts.saveSegment(segment("Raise a glass", 20, "To Anna and Sam!"), performanceID: toast.id)
            _ = try scripts.publishDraft(performanceID: toast.id, changeNote: "")
            try performances.archive(id: toast.id)

            var liveID: UUID?
            if withLiveRun {
                clock.date = Date().addingTimeInterval(-600)
                let live = try rehearsals.start(RehearsalConfig(performanceID: performance.id, versionID: v2.id, mode: .manual,
                                                                startSegmentID: nil, includeOptional: true))
                let engine = RehearsalEngine(run: live, now: { clock.uptime }, wallClock: { clock.date })
                clock.advance(64)
                engine.next(from: 0)
                clock.advance(162)
                engine.pause()
                try rehearsals.save(engine.checkpoint())
                liveID = live.id
            }
            performances.touch(id: performance.id)
            ids = (performance.id, segments[2].id, runA.id, runB.id, runV1.id, liveID)
        } catch {
            assertionFailure("Debug seed failed: \(error)")
        }
    }
}
#endif
