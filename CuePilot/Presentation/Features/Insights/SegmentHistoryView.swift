import Combine
import SwiftUI

@MainActor
final class SegmentHistoryViewModel: ObservableObject {
    enum Window: Int, CaseIterable, Identifiable {
        case five = 5, ten = 10
        var id: Int { rawValue }
        var title: String { "Last \(rawValue) runs" }
    }

    enum Order: String, CaseIterable, Identifiable {
        case script, growingFirst
        var id: String { rawValue }
        var title: String { self == .script ? "Script order" : "Growing first" }
    }

    @Published var window: Window = .ten { didSet { reload() } }
    @Published var order: Order = .script
    @Published private(set) var history: PerformanceHistory?
    @Published private(set) var trimHint: TrimHint?
    @Published private(set) var performanceName = ""
    @Published private(set) var manualRunCount = 0

    let performanceID: UUID
    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, performanceID: UUID) {
        self.container = container
        self.performanceID = performanceID
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        performanceName = container.performances.performance(id: performanceID)?.name ?? ""
        manualRunCount = container.insights.manualRunCount(performanceID: performanceID)
        history = container.insights.history(performanceID: performanceID, limit: window.rawValue)
        trimHint = container.insights.latestTrimHint(performanceID: performanceID)
    }

    var segments: [SegmentHistory] {
        guard let history else { return [] }
        guard order == .growingFirst else { return history.segments }
        func rank(_ trend: SegmentTrend) -> Int {
            switch trend {
            case .growing: return 0
            case .mixed: return 1
            case .steady: return 2
            case .shrinking: return 3
            case .notEnoughRuns: return 4
            }
        }
        return history.segments.sorted {
            let (a, b) = (rank($0.trend), rank($1.trend))
            if a != b { return a < b }
            return ($0.change ?? Int.min) > ($1.change ?? Int.min)
        }
    }
}

/// Segment History — how each segment's actual time moved across recent Manual Next runs.
struct SegmentHistoryView: View {
    @StateObject private var model: SegmentHistoryViewModel
    @EnvironmentObject private var router: Router

    init(container: AppContainer, performanceID: UUID) {
        _model = StateObject(wrappedValue: SegmentHistoryViewModel(container: container, performanceID: performanceID))
    }

    var body: some View {
        ScreenScaffold(title: "Segment History", subtitle: model.performanceName, backAction: { router.pop() }) {
            if model.manualRunCount == 0 {
                EmptyStateView(asset: ArtAsset.notebook, size: CGSize(width: 88, height: 76),
                               title: "No Manual runs yet",
                               message: "Finish a Manual Next run and each segment starts building a timing history here. Auto Advance runs follow the schedule, so they aren't included.")
            } else {
                if let hint = model.trimHint {
                    TrimHintCard(hint: hint)
                }
                trendSummary
                controls
                legend
                ForEach(model.segments) { item in
                    SegmentHistoryCard(item: item) {
                        router.push(.segmentEditor(performanceID: model.performanceID, segmentID: item.segment.id))
                    }
                }
                Text("Each bar is one Manual Next run, oldest on the left. A gap means the segment was skipped, unfinished, not reached or not in that version — it never counts as zero. Segments removed from the script aren't shown.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trendSummary: some View {
        CueCard {
            HStack(alignment: .top, spacing: 12) {
                Illustration(ArtAsset.comparisonCards, size: CGSize(width: 72, height: 64))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.history?.runs.count ?? 0) Manual run(s) in view")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    trendLine(model.history?.growing ?? [], trend: .growing, empty: "No segment grew three runs in a row.")
                    trendLine(model.history?.shrinking ?? [], trend: .shrinking, empty: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func trendLine(_ items: [SegmentHistory], trend: SegmentTrend, empty: String?) -> some View {
        if !items.isEmpty {
            Label(trend.title + ": " + items.map(\.segment.title).joined(separator: ", "), systemImage: trend.symbol)
                .font(Typo.callout)
                .foregroundColor(trend == .growing ? Palette.redInk : Palette.blueInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if let empty {
            Text(empty)
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Runs", selection: $model.window) {
                ForEach(SegmentHistoryViewModel.Window.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Order", selection: $model.order) {
                ForEach(SegmentHistoryViewModel.Order.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Palette.midnightLift, text: "Within plan")
            legendItem(color: Palette.stageRed, text: "Over plan")
            HStack(spacing: 5) {
                Rectangle().fill(Palette.ink.opacity(0.75)).frame(width: 14, height: 2)
                Text("Plan").font(Typo.caption).foregroundColor(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(Typo.caption).foregroundColor(Palette.muted)
        }
    }
}

private struct SegmentHistoryCard: View {
    let item: SegmentHistory
    let onOpenInDraft: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(item.position). \(item.segment.title)")
                    .font(Typo.headline)
                    .foregroundColor(Palette.ink)
                if item.segment.isOptional { StatusBadge.optional }
                Spacer(minLength: 6)
                TrendBadge(trend: item.trend)
            }
            SegmentHistoryChart(points: item.points, maxValue: item.maxValue)
            HStack(spacing: 14) {
                stat("Latest", item.latest?.actual.map(TimeFormat.clock) ?? "—")
                stat("Plan now", TimeFormat.clock(item.segment.plannedSeconds))
                stat("Since first", item.change.map(TimeFormat.delta) ?? "—")
                Spacer(minLength: 0)
            }
            ChipButton(title: "Open Segment in Draft", systemImage: "square.and.pencil", action: onOpenInDraft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(Typo.eyebrow).foregroundColor(Palette.muted)
            Text(value).font(Typo.monoHeadline).foregroundColor(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrendBadge: View {
    let trend: SegmentTrend

    var body: some View {
        StatusBadge(trend.title, systemImage: trend.symbol, style: style)
    }

    private var style: StatusBadge.Style {
        switch trend {
        case .growing: return .red
        case .shrinking: return .blue
        case .mixed: return .yellow
        case .steady, .notEnoughRuns: return .neutral
        }
    }
}

/// Bar per run, oldest first. Over-plan bars are red, the plan is a dark tick, gaps are dashed rings — never a zero bar.
struct SegmentHistoryChart: View {
    let points: [SegmentHistoryPoint]
    let maxValue: Int
    var barAreaHeight: CGFloat = 76

    private var latestIndex: Int? { points.lastIndex { $0.actual != nil } }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                VStack(spacing: 3) {
                    bar(point, isLatest: index == latestIndex)
                        .frame(height: barAreaHeight)
                    // Exact time under each bar: bars start at zero, so small changes need the number.
                    Text(point.actual.map(TimeFormat.clock) ?? "—")
                        .font(.system(size: 9, weight: index == latestIndex ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundColor((point.over ?? 0) > 0 ? Palette.redInk : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(versionLabel(index))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Palette.muted)
                        .lineLimit(1)
                        .frame(height: 10)
                }
                .frame(maxWidth: 34)
            }
            if points.count < 5 {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func bar(_ point: SegmentHistoryPoint, isLatest: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Palette.paperShade.opacity(0.7))
            if let actual = point.actual {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill((point.over ?? 0) > 0 ? Palette.stageRed : Palette.midnightLift)
                    .frame(height: height(actual))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isLatest ? Palette.spotlight : .clear, lineWidth: 2.5)
                    )
            } else {
                Circle()
                    .strokeBorder(Palette.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                    .padding(.bottom, 4)
            }
            if let planned = point.planned {
                Rectangle()
                    .fill(Palette.ink.opacity(0.75))
                    .frame(height: 2)
                    .padding(.bottom, max(0, height(planned) - 1))
                    .padding(.horizontal, -2)
            }
        }
    }

    private func height(_ seconds: Int) -> CGFloat {
        max(3, barAreaHeight * CGFloat(seconds) / CGFloat(max(maxValue, 1)))
    }

    /// Version under each bar, only where it changes — so a new script version is easy to spot.
    private func versionLabel(_ index: Int) -> String {
        let number = points[index].versionNumber
        if index == 0 || points[index - 1].versionNumber != number { return "v\(number)" }
        return ""
    }

    private var accessibilitySummary: String {
        let values = points.map { point -> String in
            guard let actual = point.actual else { return "gap" }
            return TimeFormat.spoken(actual) + ((point.over ?? 0) > 0 ? " over plan" : "")
        }
        return "Oldest to newest: " + values.joined(separator: ", ")
    }
}
