import Combine
import SwiftUI

@MainActor
final class ExportStudioViewModel: ObservableObject {
    @Published var kind: ExportKind { didSet { if oldValue != kind { adjustOptionsForKind() } } }
    @Published var performanceID: UUID? { didSet { if oldValue != performanceID { performanceChanged() } } }
    @Published var versionID: UUID?
    @Published var runID: UUID?
    @Published var runAID: UUID?
    @Published var runBID: UUID?
    @Published var options = ExportOptions()
    @Published private(set) var performances: [Performance] = []
    @Published private(set) var versions: [ScriptVersion] = []
    @Published private(set) var runs: [RehearsalRun] = []
    @Published var previewData: Data?
    @Published var share: ShareItem?
    @Published var alert: AlertMessage?

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, preset: ExportPreset) {
        self.container = container
        kind = preset.kind
        let fromRun = (preset.runID ?? preset.runB).flatMap { container.rehearsals.run(id: $0) }
        performanceID = preset.performanceID ?? fromRun?.performanceID ?? container.performances.currentPerformance()?.id
        reloadLists()
        versionID = preset.versionID ?? defaultVersionID()
        runID = preset.runID ?? runs.first?.id
        if preset.runA != nil || preset.runB != nil {
            runAID = preset.runA
            runBID = preset.runB
        } else if let pair = RunComparison.defaultPair(from: runs, preferredVersionID: nil) {
            runAID = pair.a.id
            runBID = pair.b.id
        }
        container.databaseChanges
            .dropFirst()
            .sink { [weak self] _ in self?.reloadLists() }
            .store(in: &cancellables)
    }

    private func reloadLists() {
        performances = container.performances.performances(archived: false) + container.performances.performances(archived: true)
        guard let performanceID else {
            versions = []
            runs = []
            return
        }
        versions = container.scripts.versions(performanceID: performanceID)
        runs = container.rehearsals.runs(performanceID: performanceID)
    }

    private func performanceChanged() {
        reloadLists()
        versionID = defaultVersionID()
        runID = runs.first?.id
        let pair = RunComparison.defaultPair(from: runs, preferredVersionID: nil)
        runAID = pair?.a.id
        runBID = pair?.b.id
        previewData = nil
    }

    /// The current published version, or the draft when nothing is published yet.
    private func defaultVersionID() -> UUID? {
        performanceID.flatMap { container.scripts.currentPublished(performanceID: $0)?.id } ?? versions.first?.id
    }

    private func adjustOptionsForKind() {
        previewData = nil
        // Private fields stay off unless chosen for this export.
        options.includeReflection = false
    }

    var selectedPerformance: Performance? { performances.first { $0.id == performanceID } }
    var selectedVersion: ScriptVersion? { versions.first { $0.id == versionID } }
    var selectedRun: RehearsalRun? { runs.first { $0.id == runID } }
    var runA: RehearsalRun? { runs.first { $0.id == runAID } }
    var runB: RehearsalRun? { runs.first { $0.id == runBID } }

    /// The source is always named explicitly, including the script version.
    var sourceDescription: String? {
        switch kind {
        case .cueSheet:
            guard let performance = selectedPerformance, let version = selectedVersion else { return nil }
            return "\(performance.name) · \(version.displayName) · \(version.isDraft ? "Draft" : "Published")"
        case .runSummary:
            guard let run = selectedRun else { return nil }
            return "Run of \(DateText.short(run.startedAt)) · \(run.snapshot.versionDisplayName) · \(run.mode.title)"
        case .comparison:
            guard let a = runA, let b = runB else { return nil }
            return "A: \(DateText.short(a.startedAt)) (\(a.snapshot.versionDisplayName)) vs B: \(DateText.short(b.startedAt)) (\(b.snapshot.versionDisplayName))"
        }
    }

    /// Why export is blocked right now, if it is.
    var blockingReason: String? {
        switch kind {
        case .cueSheet:
            guard let version = selectedVersion else { return "Choose a performance and a version to export." }
            if version.segments.isEmpty { return "This version has no segments yet — add some before exporting a cue sheet." }
        case .runSummary:
            if selectedRun == nil { return "Choose a finished run to export its summary." }
        case .comparison:
            guard let a = runA, let b = runB else { return "Choose two finished runs to compare." }
            if case let .blocked(reason) = RunComparison.eligibility(a, b) { return reason }
        }
        return nil
    }

    var source: ExportSource? {
        guard blockingReason == nil else { return nil }
        switch kind {
        case .cueSheet: return versionID.map { .cueSheet(versionID: $0) }
        case .runSummary: return runID.map { .runSummary(runID: $0) }
        case .comparison:
            guard let a = runAID, let b = runBID else { return nil }
            return .comparison(runA: a, runB: b)
        }
    }

    func preview() {
        guard let source else { return }
        do {
            previewData = try container.exports.pdfData(for: source, options: options)
        } catch {
            alert = AlertMessage(title: "Preview failed", error)
        }
    }

    func exportPDF() {
        guard let source else { return }
        do {
            share = ShareItem(urls: [try container.exports.exportPDF(for: source, options: options)])
        } catch {
            alert = AlertMessage(title: "Export failed", error)
        }
    }

    func exportCSV() {
        guard let source else { return }
        do {
            share = ShareItem(urls: [try container.exports.exportCSV(for: source, options: options)])
        } catch {
            alert = AlertMessage(title: "Export failed", error)
        }
    }

    func shareBoth() {
        guard let source else { return }
        do {
            let pdf = try container.exports.exportPDF(for: source, options: options)
            let csv = try container.exports.exportCSV(for: source, options: options)
            share = ShareItem(urls: [pdf, csv])
        } catch {
            alert = AlertMessage(title: "Export failed", error)
        }
    }
}

/// Export Studio — cue sheets, run summaries and comparisons as PDF or timing CSV via the system Share sheet.
struct ExportStudioView: View {
    @StateObject private var model: ExportStudioViewModel
    @EnvironmentObject private var router: Router
    @State private var showPreview = false

    init(container: AppContainer, preset: ExportPreset) {
        _model = StateObject(wrappedValue: ExportStudioViewModel(container: container, preset: preset))
    }

    var body: some View {
        ScreenScaffold(title: "Export Studio", subtitle: model.kind.title, backAction: { router.pop() }) {
            HStack(spacing: 14) {
                Illustration(ArtAsset.notebook, size: CGSize(width: 64, height: 55))
                Text("Documents are built from your real data only — timing, cues and your own notes. No ratings.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Export Type", selection: $model.kind) {
                ForEach(ExportKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            sourceCard
            optionsCard

            if let reason = model.blockingReason {
                NoticeBanner(text: reason, systemImage: "exclamationmark.circle.fill", tone: .warning)
            } else if let description = model.sourceDescription {
                NoticeBanner(text: "Source: \(description)", systemImage: "doc.text")
            }

            Button {
                model.preview()
                if model.previewData != nil { showPreview = true }
            } label: {
                Label("Preview", systemImage: "doc.richtext")
            }
            .buttonStyle(.cueSecondary)
            .disabled(model.source == nil)

            Button {
                model.exportPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.cuePrimary)
            .disabled(model.source == nil)

            HStack(spacing: 10) {
                Button {
                    model.exportCSV()
                } label: {
                    Label("Export Timing CSV", systemImage: "tablecells")
                }
                .buttonStyle(.cueSecondary)
                Button {
                    model.shareBoth()
                } label: {
                    Label("Share Both", systemImage: "square.and.arrow.up.on.square")
                }
                .buttonStyle(.cueSecondary)
            }
            .disabled(model.source == nil)
        }
        .alert($model.alert)
        .sheet(item: $model.share) { item in
            ShareSheet(items: item.urls)
        }
        .sheet(isPresented: $showPreview) {
            if let data = model.previewData {
                VStack(spacing: 0) {
                    HStack {
                        Text("PDF Preview")
                            .font(Typo.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Share") {
                            showPreview = false
                            model.exportPDF()
                        }
                        .foregroundColor(Palette.spotlight)
                        .frame(minHeight: Metrics.minTap)
                        Button("Close") { showPreview = false }
                            .foregroundColor(Palette.spotlight)
                            .frame(minWidth: Metrics.minTap, minHeight: Metrics.minTap)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(HeaderBackground())
                    PDFPreview(data: data)
                }
            }
        }
    }

    private var sourceCard: some View {
        CueCard {
            menuRow(label: "Performance", value: model.selectedPerformance?.name ?? "Choose") {
                ForEach(model.performances) { performance in
                    Button(performance.name + (performance.isArchived ? " (Archived)" : "")) { model.performanceID = performance.id }
                }
            }
            switch model.kind {
            case .cueSheet:
                menuRow(label: "Version", value: model.selectedVersion.map { "\($0.displayName) · \($0.isDraft ? "Draft" : "Published")" } ?? "Choose") {
                    ForEach(model.versions) { version in
                        Button("\(version.displayName) · \(version.isDraft ? "Draft" : "Published")") { model.versionID = version.id }
                    }
                }
            case .runSummary:
                menuRow(label: "Run", value: model.selectedRun.map(runTitle) ?? "Choose") {
                    ForEach(model.runs) { run in
                        Button(runTitle(run)) { model.runID = run.id }
                    }
                }
            case .comparison:
                menuRow(label: "Run A", value: model.runA.map(runTitle) ?? "Choose") {
                    ForEach(model.runs) { run in
                        Button(runTitle(run)) { model.runAID = run.id }
                    }
                }
                menuRow(label: "Run B", value: model.runB.map(runTitle) ?? "Choose") {
                    ForEach(model.runs) { run in
                        Button(runTitle(run)) { model.runBID = run.id }
                    }
                }
            }
        }
    }

    private func runTitle(_ run: RehearsalRun) -> String {
        "\(DateText.short(run.startedAt)) · \(run.snapshot.versionDisplayName) · \(run.mode.shortTitle)"
    }

    private var optionsCard: some View {
        CueCard {
            Toggle(isOn: $model.options.includeDetailedNotes) {
                optionLabel("Include Detailed Notes", "Private preparation notes. Off by default.")
            }
            .tint(Palette.midnight)
            if model.kind != .cueSheet {
                Toggle(isOn: $model.options.includeMarkers) {
                    optionLabel("Include Markers", "Your own on-stage bookmarks with type and note.")
                }
                .tint(Palette.midnight)
                Toggle(isOn: $model.options.includeReflection) {
                    optionLabel("Include Reflection", "Private notes you wrote after the run. Off by default.")
                }
                .tint(Palette.midnight)
            }
        }
    }

    private func optionLabel(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Palette.ink)
            Text(caption)
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
        }
    }

    private func menuRow<Items: View>(label: String, value: String, @ViewBuilder items: () -> Items) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: true)
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
        }
    }
}
