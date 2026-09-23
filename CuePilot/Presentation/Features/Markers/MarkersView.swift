import Combine
import SwiftUI

@MainActor
final class MarkersViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let marker: RunMarker
        let segmentTitle: String
        let segmentPosition: Int
        var id: UUID { marker.id }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var run: RehearsalRun?
    @Published var alert: AlertMessage?

    let runID: UUID
    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, runID: UUID) {
        self.container = container
        self.runID = runID
        container.databaseChanges
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    var isLive: Bool { run?.isLive ?? false }

    func reload() {
        run = container.rehearsals.run(id: runID)
        guard let run else {
            rows = []
            return
        }
        // Titles and positions come from the run's own snapshot, never from the current script.
        let positions = Dictionary(run.snapshot.segments.enumerated().map { ($1.id, ($0 + 1, $1.title)) }, uniquingKeysWith: { first, _ in first })
        rows = container.rehearsals.markers(runID: runID).map { marker in
            let info = positions[marker.segmentID] ?? (0, "Unknown segment")
            return Row(marker: marker, segmentTitle: info.1, segmentPosition: info.0)
        }
    }

    func update(_ marker: RunMarker, type: MarkerType, note: String) -> Bool {
        do {
            try container.rehearsals.updateMarker(id: marker.id, type: type, note: note)
            return true
        } catch {
            alert = AlertMessage(error)
            return false
        }
    }

    func setType(_ type: MarkerType, for marker: RunMarker) {
        _ = update(marker, type: type, note: marker.note)
    }

    func delete(_ marker: RunMarker) {
        do { try container.rehearsals.deleteMarker(id: marker.id) } catch { alert = AlertMessage(error) }
    }
}

/// Run Markers — turn quick on-stage bookmarks into clear notes.
struct MarkersView: View {
    enum Context {
        case pushed
        /// Opened from a paused Stage; closing returns to the run.
        case stageSheet(onClose: () -> Void)
    }

    @StateObject private var model: MarkersViewModel
    @EnvironmentObject private var router: Router
    let context: Context
    @State private var editing: RunMarker?
    @State private var deleting: RunMarker?

    init(container: AppContainer, runID: UUID, context: Context) {
        _model = StateObject(wrappedValue: MarkersViewModel(container: container, runID: runID))
        self.context = context
    }

    var body: some View {
        content
            .alert($model.alert)
            .sheet(item: $editing) { marker in
                MarkerEditSheet(marker: marker, segmentTitle: model.rows.first { $0.id == marker.id }?.segmentTitle ?? "",
                                onCancel: { editing = nil },
                                onSave: { type, note in
                                    if model.update(marker, type: type, note: note) { editing = nil }
                                },
                                onDelete: {
                                    editing = nil
                                    model.delete(marker)
                                })
            }
            .confirmationDialog("Delete this marker?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Delete Marker", role: .destructive) {
                    if let deleting { model.delete(deleting) }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: {
                Text("The run's timing is not affected.")
            }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch context {
        case .pushed:
            ScreenScaffold(title: "Markers", subtitle: model.run.map { "\($0.snapshot.performanceName) · \(DateText.short($0.startedAt))" },
                           backAction: { router.pop() }) {
                list
                if model.run?.isLive == false {
                    Button {
                        router.show(.review(runID: model.runID))
                    } label: {
                        Label("Open Review", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.cueSecondary)
                }
            }
        case let .stageSheet(onClose):
            SheetScaffold(title: "Markers", closeTitle: "Back to Run", onClose: onClose) {
                NoticeBanner(text: "The run is paused. Markers keep the time they were dropped at; editing only changes the type and note.",
                             systemImage: "pause.circle.fill", tone: .spotlight)
                list
                Button("Back to Run", action: onClose)
                    .buttonStyle(.cuePrimary)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.rows.isEmpty {
            EmptyStateView(asset: ArtAsset.reviewMarker, size: CGSize(width: 48, height: 64),
                           title: "No markers",
                           message: "Tap Marker on stage whenever a moment needs another look. It's your own bookmark — nothing is detected automatically.")
        } else {
            HStack(spacing: 12) {
                Illustration(ArtAsset.reviewMarker, size: CGSize(width: 48, height: 64))
                Text("\(model.rows.count) marker(s). Give each a type and a note so it's clear later what to change.")
                    .font(Typo.callout)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                ForEach(model.rows) { row in
                    MarkerRow(row: row,
                              onType: { model.setType($0, for: row.marker) },
                              onEdit: { editing = row.marker },
                              onDelete: { deleting = row.marker })
                }
            }
        }
    }
}

private struct MarkerRow: View {
    let row: MarkersViewModel.Row
    let onType: (MarkerType) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        CueCard(accent: Palette.stageRed, padding: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(row.segmentPosition). \(row.segmentTitle)")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text("\(TimeFormat.clock(row.marker.segmentOffsetSeconds)) into segment · \(TimeFormat.clock(row.marker.totalOffsetSeconds)) total")
                        .font(Typo.monoCaption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
                Menu {
                    ForEach(MarkerType.allCases) { type in
                        Button { onType(type) } label: { Label(type.title, systemImage: type.symbol) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: row.marker.type.symbol)
                        Text(row.marker.type.title)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(Typo.captionBold)
                    .foregroundColor(Palette.redInk)
                    .padding(.horizontal, 10)
                    .frame(minHeight: Metrics.minTap)
                    .background(Capsule().fill(Palette.stageRed.opacity(0.1)))
                }
                .accessibilityLabel("Marker type: \(row.marker.type.title)")
            }
            if row.marker.note.isEmpty {
                Button(action: onEdit) {
                    Label("Add Note", systemImage: "text.badge.plus")
                }
                .buttonStyle(.cue(.plain, fullWidth: false, compact: true))
            } else {
                Text(row.marker.note)
                    .font(Typo.body)
                    .foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ChipButton(title: "Edit Marker", systemImage: "square.and.pencil", action: onEdit)
                ChipButton(title: "Delete", systemImage: "trash", tint: Palette.redInk, action: onDelete)
            }
        }
    }
}

private struct MarkerEditSheet: View {
    let marker: RunMarker
    let segmentTitle: String
    let onCancel: () -> Void
    let onSave: (MarkerType, String) -> Void
    let onDelete: () -> Void
    @State private var type: MarkerType
    @State private var note: String

    init(marker: RunMarker, segmentTitle: String, onCancel: @escaping () -> Void,
         onSave: @escaping (MarkerType, String) -> Void, onDelete: @escaping () -> Void) {
        self.marker = marker
        self.segmentTitle = segmentTitle
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _type = State(initialValue: marker.type)
        _note = State(initialValue: marker.note)
    }

    var body: some View {
        SheetScaffold(title: "Edit Marker", closeTitle: "Cancel", onClose: onCancel) {
            CueCard {
                InfoRow(label: "Segment", value: segmentTitle)
                InfoRow(label: "Segment Time", value: TimeFormat.clock(marker.segmentOffsetSeconds), monospaced: true)
                Text("The time is fixed to the run's script snapshot and doesn't change when you edit the script.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(label: "Marker Type")
                Picker("Marker Type", selection: $type) {
                    ForEach(MarkerType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            CueTextEditor(label: "Note", text: $note, placeholder: "What should change here? (optional)",
                          limit: Limits.markerNoteMax, minHeight: 110)
            Button("Save Marker") { onSave(type, note) }
                .buttonStyle(.cuePrimary)
                .disabled(note.count > Limits.markerNoteMax)
            Button(role: .destructive, action: onDelete) {
                Label("Delete Marker", systemImage: "trash")
            }
            .buttonStyle(.cueDestructive)
        }
    }
}
