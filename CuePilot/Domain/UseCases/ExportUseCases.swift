import Foundation

// MARK: - Export document model (format-independent)

struct ExportTable: Equatable {
    var columns: [String]
    var rows: [[String]]
    /// Relative column widths for the PDF layout.
    var weights: [Double]
    /// Row indices drawn with emphasis (for example a totals row).
    var emphasizedRows: Set<Int> = []
}

struct ExportSection: Equatable {
    var heading: String
    var paragraphs: [String] = []
    var table: ExportTable?
    var bullets: [String] = []
}

struct ExportDocument: Equatable {
    var kindTitle: String
    var title: String
    /// Always names the source and the script version the data comes from.
    var sourceLine: String
    var metaLines: [String]
    var sections: [ExportSection]
    var footer: String
    /// Timing data for the CSV export.
    var timingTable: ExportTable
    var fileBaseName: String
}

enum ExportKind: String, CaseIterable, Identifiable {
    case cueSheet, runSummary, comparison

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cueSheet: return "Cue Sheet"
        case .runSummary: return "Run Summary"
        case .comparison: return "Comparison"
        }
    }
}

struct ExportOptions: Equatable {
    /// Private by default.
    var includeDetailedNotes = false
    var includeMarkers = true
    /// Private by default.
    var includeReflection = false
}

enum ExportSource: Equatable {
    case cueSheet(versionID: UUID)
    case runSummary(runID: UUID)
    case comparison(runA: UUID, runB: UUID)
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Builds export documents from real data only — no scores, no decorative ratings.
final class ExportUseCases {
    private let store: DataStore
    private let renderer: ExportRendering
    private let files: FileExporting
    private let clock: () -> Date

    init(store: DataStore, renderer: ExportRendering, files: FileExporting, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.renderer = renderer
        self.files = files
        self.clock = clock
    }

    func document(for source: ExportSource, options: ExportOptions) throws -> ExportDocument {
        let db = store.database
        switch source {
        case let .cueSheet(versionID):
            guard let version = db.versions.first(where: { $0.id == versionID }),
                  let performance = db.performances.first(where: { $0.id == version.performanceID }) else {
                throw DomainError.notFound("Version")
            }
            guard !version.segments.isEmpty else {
                throw DomainError.exportFailed("this version has no segments yet")
            }
            return cueSheet(performance: performance, version: version, options: options)
        case let .runSummary(runID):
            guard let run = db.runs.first(where: { $0.id == runID }) else { throw DomainError.notFound("Run") }
            guard !run.isLive else { throw DomainError.runStillLive }
            let markers = db.markers.filter { $0.runID == runID }.sorted { $0.totalOffsetSeconds < $1.totalOffsetSeconds }
            return runSummary(review: RunReview.build(run: run, markers: markers), options: options)
        case let .comparison(aID, bID):
            guard let a = db.runs.first(where: { $0.id == aID }), let b = db.runs.first(where: { $0.id == bID }) else {
                throw DomainError.notFound("Run")
            }
            if case let .blocked(reason) = RunComparison.eligibility(a, b) { throw DomainError.runsNotComparable(reason) }
            let comparison = RunComparison.build(
                a: a, b: b,
                markersA: db.markers.filter { $0.runID == aID },
                markersB: db.markers.filter { $0.runID == bID }
            )
            return self.comparison(comparison, options: options)
        }
    }

    func exportPDF(for source: ExportSource, options: ExportOptions) throws -> URL {
        let document = try document(for: source, options: options)
        do {
            let data = try renderer.pdf(for: document)
            return try files.write(data: data, fileName: document.fileBaseName + ".pdf")
        } catch let error as DomainError {
            throw error
        } catch {
            throw DomainError.exportFailed(error.localizedDescription)
        }
    }

    func pdfData(for source: ExportSource, options: ExportOptions) throws -> Data {
        let document = try document(for: source, options: options)
        do {
            return try renderer.pdf(for: document)
        } catch {
            throw DomainError.exportFailed(error.localizedDescription)
        }
    }

    func exportCSV(for source: ExportSource, options: ExportOptions) throws -> URL {
        let document = try document(for: source, options: options)
        do {
            return try files.write(data: renderer.csv(for: document.timingTable), fileName: document.fileBaseName + "-timing.csv")
        } catch {
            throw DomainError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: Builders

    private func footer() -> String {
        "Generated by Cue Pilot on \(DateText.short(clock())). Timing and your own notes only — no automatic assessment of the performance."
    }

    private func cueSheet(performance: Performance, version: ScriptVersion, options: ExportOptions) -> ExportDocument {
        let statusText = version.isDraft ? "Draft (not yet published)" : "Published \(version.publishedAt.map(DateText.day) ?? "")"
        var meta = [
            "Type: \(performance.type.title)",
            "Segments: \(version.segments.count) · Planned total: \(TimeFormat.clock(version.plannedTotalSeconds))"
        ]
        if let target = performance.targetTotalSeconds {
            let gap = version.plannedTotalSeconds - target
            meta.append("Personal target: \(TimeFormat.clock(target)) (\(gap == 0 ? "matches plan" : "plan is \(TimeFormat.delta(gap)) vs target"))")
        }
        var rows: [[String]] = []
        var elapsed = 0
        for (index, segment) in version.segments.enumerated() {
            let start = TimeFormat.clock(elapsed)
            elapsed += segment.plannedSeconds
            let cue = segment.cueText.trimmed
            rows.append([
                "\(index + 1)",
                segment.title + (segment.isOptional ? " (Optional)" : ""),
                TimeFormat.clock(segment.plannedSeconds),
                start,
                cue.isEmpty ? "—" : cue
            ])
        }
        var sections: [ExportSection] = []
        if !version.generalNote.trimmed.isEmpty {
            sections.append(ExportSection(heading: "General Note", paragraphs: [version.generalNote.trimmed]))
        }
        sections.append(ExportSection(
            heading: "Running Order",
            table: ExportTable(columns: ["#", "Segment", "Plan", "Starts", "Cue"], rows: rows, weights: [0.5, 2.2, 0.9, 0.9, 4.2])
        ))
        if options.includeDetailedNotes {
            let notes = version.segments.enumerated().filter { !$0.element.detailedNotes.trimmed.isEmpty }
                .map { "\($0.offset + 1). \($0.element.title): \($0.element.detailedNotes.trimmed)" }
            if !notes.isEmpty { sections.append(ExportSection(heading: "Detailed Notes", bullets: notes)) }
        }
        let csv = ExportTable(
            columns: ["Order", "Segment", "Optional", "Planned (s)", "Planned", "Starts At", "Cue"],
            rows: {
                var running = 0
                return version.segments.enumerated().map { index, segment in
                    defer { running += segment.plannedSeconds }
                    return ["\(index + 1)", segment.title, segment.isOptional ? "yes" : "no", "\(segment.plannedSeconds)",
                            TimeFormat.clock(segment.plannedSeconds), TimeFormat.clock(running), segment.cueText]
                }
            }(),
            weights: []
        )
        return ExportDocument(
            kindTitle: "Cue Sheet",
            title: performance.name,
            sourceLine: "Source: \(performance.name) · \(version.displayName) · \(statusText)",
            metaLines: meta,
            sections: sections,
            footer: footer(),
            timingTable: csv,
            fileBaseName: FileNames.safe("CuePilot-CueSheet-\(performance.name)-v\(version.number)")
        )
    }

    private func runSummary(review: RunReview, options: ExportOptions) -> ExportDocument {
        let run = review.run
        var meta = [
            "Started: \(DateText.short(run.startedAt)) · Mode: \(run.mode.title)",
            "Status: \(run.outcome?.title ?? "In progress")\(run.isPartial ? " · Partial Run" : "")",
            "Active time: \(TimeFormat.clock(run.totalActiveSeconds)) · Paused time: \(TimeFormat.clock(run.totalPausedSeconds))"
        ]
        if run.interruptionCount > 0 {
            meta.append("Recovered after \(run.interruptionCount) interruption(s); time while the app was closed is not counted.")
        }
        if run.mode == .autoAdvance {
            meta.append("Auto Advance run: segments switched on the planned schedule. Durations show schedule adherence, not speaking time.")
        }

        var rows: [[String]] = review.completed.map { row in
            let deviation: String
            if run.mode == .manual {
                deviation = TimeFormat.delta(row.deviation) + (row.isExceeded ? " EXCEEDED" : "")
            } else {
                deviation = row.record.advancedBy == .autoSchedule ? "On schedule" : "Advanced early"
            }
            return ["\(row.position)", row.segment.title, TimeFormat.clock(row.segment.plannedSeconds),
                    TimeFormat.clock(row.actualSeconds), deviation, options.includeMarkers ? "\(row.markers.count)" : "—"]
        }
        var emphasized: Set<Int> = []
        if !review.completed.isEmpty {
            emphasized.insert(rows.count)
            rows.append(["", "Completed segments", TimeFormat.clock(review.plannedForCompleted), TimeFormat.clock(review.actualForCompleted),
                         review.manualDeviationTotal.map(TimeFormat.delta) ?? "—", ""])
        }
        var sections = [ExportSection(
            heading: "Planned vs Actual",
            paragraphs: review.completed.isEmpty ? ["No segment was completed in this run."] : [],
            table: review.completed.isEmpty ? nil : ExportTable(
                columns: ["#", "Segment", "Plan", "Actual", run.mode == .manual ? "Deviation" : "Schedule", "Markers"],
                rows: rows, weights: [0.5, 3.0, 1.0, 1.0, 1.6, 0.9], emphasizedRows: emphasized
            )
        )]

        var notCounted: [String] = []
        notCounted += review.skipped.map { "\($0.position). \($0.segment.title) — Skipped (optional)" }
        notCounted += review.unfinished.map { "\($0.position). \($0.segment.title) — Unfinished when the run ended" }
        notCounted += review.notReached.map { "\($0.position). \($0.segment.title) — Not reached" }
        notCounted += review.excluded.map { "\($0.position). \($0.segment.title) — Optional, excluded at setup" }
        notCounted += review.beforeStart.map { "\($0.position). \($0.segment.title) — Before the chosen start" }
        if !notCounted.isEmpty {
            sections.append(ExportSection(heading: "Not Counted in Timing", bullets: notCounted))
        }
        if options.includeMarkers, !review.markers.isEmpty {
            let titles = Dictionary(run.snapshot.segments.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            sections.append(ExportSection(
                heading: "Markers",
                table: ExportTable(
                    columns: ["Segment", "At", "Type", "Note"],
                    rows: review.markers.map { marker in
                        [titles[marker.segmentID] ?? "—", TimeFormat.clock(marker.segmentOffsetSeconds), marker.type.title,
                         marker.note.isEmpty ? "—" : marker.note]
                    },
                    weights: [2.2, 0.9, 1.1, 3.8]
                )
            ))
        }
        if options.includeReflection, !run.reflection.trimmed.isEmpty {
            sections.append(ExportSection(heading: "Reflection", paragraphs: [run.reflection.trimmed]))
        }
        if options.includeDetailedNotes {
            let notes = run.snapshot.segments.enumerated().filter { !$0.element.detailedNotes.trimmed.isEmpty }
                .map { "\($0.offset + 1). \($0.element.title): \($0.element.detailedNotes.trimmed)" }
            if !notes.isEmpty { sections.append(ExportSection(heading: "Detailed Notes", bullets: notes)) }
        }

        let csv = ExportTable(
            columns: ["Order", "Segment", "Status", "Planned (s)", "Actual (s)", "Deviation (s)", "Paused (s)", "Advanced By", "Markers"],
            rows: run.snapshot.segments.enumerated().map { index, segment in
                let record = run.records[index]
                let completed = record.status == .completed
                let actual = TimeFormat.wholeSeconds(record.activeSeconds)
                return ["\(index + 1)", segment.title, record.status.title, "\(segment.plannedSeconds)",
                        completed ? "\(actual)" : "", completed && run.mode == .manual ? "\(actual - segment.plannedSeconds)" : "",
                        "\(TimeFormat.wholeSeconds(record.pausedSeconds))", record.advancedBy?.rawValue ?? "",
                        options.includeMarkers ? "\(review.markers.filter { $0.segmentID == segment.id }.count)" : ""]
            },
            weights: []
        )
        return ExportDocument(
            kindTitle: "Run Summary",
            title: run.snapshot.performanceName,
            sourceLine: "Source: run of \(DateText.short(run.startedAt)) · \(run.snapshot.versionDisplayName) · \(run.mode.title)",
            metaLines: meta,
            sections: sections,
            footer: footer(),
            timingTable: csv,
            fileBaseName: FileNames.safe("CuePilot-Run-\(run.snapshot.performanceName)-\(DateText.fileStamp(run.startedAt))")
        )
    }

    private func comparison(_ comparison: RunComparison, options: ExportOptions) -> ExportDocument {
        let a = comparison.runA, b = comparison.runB
        var meta = [
            "Run A: \(DateText.short(a.startedAt)) · \(a.snapshot.versionDisplayName) · \(a.outcome?.title ?? "")",
            "Run B: \(DateText.short(b.startedAt)) · \(b.snapshot.versionDisplayName) · \(b.outcome?.title ?? "")",
            "Mode: \(a.mode.title) · Difference is B − A, only for segments completed in both runs."
        ]
        if !comparison.sameVersion {
            meta.append("Different script versions: segments are matched by their stable ID, not by position. Changed segments are marked.")
        }
        func cellText(_ cell: ComparisonCell) -> String {
            switch cell {
            case let .completed(actual, _): return TimeFormat.clock(actual)
            case let .notCounted(status): return status.title
            }
        }
        var rows = comparison.rows.map { row -> [String] in
            var title = row.title
            if row.isChanged { title += " (Changed: " + row.changes.map(\.label).joined(separator: ", ") + ")" }
            var markers = ""
            if options.includeMarkers { markers = "\(row.markersA.count) / \(row.markersB.count)" }
            return [title, cellText(row.a), cellText(row.b), row.difference.map(TimeFormat.delta) ?? "not counted", markers]
        }
        var emphasized: Set<Int> = []
        if let total = comparison.totalDifference {
            emphasized.insert(rows.count)
            rows.append(["Total over \(comparison.countedRows.count) matched completed segment(s)", "", "", TimeFormat.delta(total), ""])
        }
        var sections = [ExportSection(
            heading: "Segment by Segment",
            table: ExportTable(columns: ["Segment", "A", "B", "Difference", options.includeMarkers ? "Markers A/B" : ""],
                               rows: rows, weights: [3.6, 1.0, 1.0, 1.3, 1.1], emphasizedRows: emphasized)
        )]
        let unmatched = comparison.onlyInA.map { "Only in A: \($0.segment.title)" } + comparison.onlyInB.map { "Only in B: \($0.segment.title)" }
        if !unmatched.isEmpty {
            sections.append(ExportSection(heading: "Unmatched Segments", bullets: unmatched))
        }
        if options.includeReflection {
            let reflections = [("A", a.reflection), ("B", b.reflection)].filter { !$0.1.trimmed.isEmpty }.map { "Run \($0.0): \($0.1.trimmed)" }
            if !reflections.isEmpty { sections.append(ExportSection(heading: "Reflections", bullets: reflections)) }
        }
        let csv = ExportTable(
            columns: ["Segment", "Position A", "Position B", "A (s)", "B (s)", "Difference B-A (s)", "Changed", "Markers A", "Markers B"],
            rows: comparison.rows.map { row in
                [row.title, "\(row.positionA)", "\(row.positionB)", row.a.actual.map(String.init) ?? row.a.statusText,
                 row.b.actual.map(String.init) ?? row.b.statusText, row.difference.map(String.init) ?? "",
                 row.isChanged ? row.changes.map(\.label).joined(separator: "; ") : "",
                 options.includeMarkers ? "\(row.markersA.count)" : "", options.includeMarkers ? "\(row.markersB.count)" : ""]
            },
            weights: []
        )
        return ExportDocument(
            kindTitle: "Run Comparison",
            title: b.snapshot.performanceName,
            sourceLine: "Source: \(a.snapshot.versionDisplayName) run of \(DateText.day(a.startedAt)) vs \(b.snapshot.versionDisplayName) run of \(DateText.day(b.startedAt))",
            metaLines: meta,
            sections: sections,
            footer: footer(),
            timingTable: csv,
            fileBaseName: FileNames.safe("CuePilot-Comparison-\(b.snapshot.performanceName)-\(DateText.fileStamp(b.startedAt))")
        )
    }
}

extension ComparisonCell {
    var statusText: String {
        switch self {
        case let .completed(actual, _): return "\(actual)"
        case let .notCounted(status): return status.title
        }
    }
}

enum FileNames {
    static func safe(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let collapsed = mapped.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(90))
    }
}
