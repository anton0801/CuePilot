import SwiftUI

/// Performance Editor — structure of the piece: details, segments, draft label/note, publish.
struct PerformanceEditorView: View {
    @StateObject private var model: PerformanceEditorViewModel
    @EnvironmentObject private var router: Router
    @State private var confirmLeave = false
    @State private var showPublish = false
    @State private var showReorder = false

    init(container: AppContainer, performanceID: UUID?) {
        _model = StateObject(wrappedValue: PerformanceEditorViewModel(container: container, performanceID: performanceID))
    }

    var body: some View {
        ScreenScaffold(
            title: model.isNew ? "New Performance" : (model.savedForm.name.isEmpty ? "Performance" : model.savedForm.name),
            subtitle: model.versionStatusText,
            backAction: back
        ) {
            if model.performanceID != nil {
                HeaderIconButton(systemName: "square.stack.3d.up", label: "Script versions") {
                    if let id = model.performanceID { router.push(.versions(performanceID: id, highlight: nil)) }
                }
            }
        } content: {
            header
            detailsCard
            segmentsSection
            versionCard
            actions
        }
        .popGestureBlocked(model.isDirty)
        .alert($model.alert)
        .confirmationDialog("You have unsaved changes", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Save Draft") { if model.saveDraft() { router.pop() } }
            Button("Discard Changes", role: .destructive) {
                model.discardChanges()
                router.pop()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $showPublish) {
            PublishDraftSheet(
                versionNumber: model.draft?.number ?? model.nextVersionNumber,
                issues: model.publishIssues,
                onCancel: { showPublish = false },
                onPublish: { note in
                    if let version = model.publish(changeNote: note) {
                        showPublish = false
                        router.push(.versions(performanceID: version.performanceID, highlight: version.id))
                    }
                }
            )
        }
        .sheet(isPresented: $showReorder) {
            ReorderSegmentsSheet(segments: model.segments, lockedVersionName: model.draft == nil ? model.currentPublished?.shortName : nil) { ids in
                model.reorder(to: ids)
                showReorder = false
            } onCancel: {
                showReorder = false
            }
        }
    }

    private func back() {
        if model.isDirty { confirmLeave = true } else { router.pop() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            Illustration(ArtAsset.scriptCards, size: CGSize(width: 72, height: 62))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isNew ? "Shape the piece" : "Structure")
                    .font(Typo.headline)
                    .foregroundColor(Palette.ink)
                Text("Split it into segments, each with a planned time and a short cue you can read at a glance.")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailsCard: some View {
        CueCard {
            CueTextField(label: "Name", text: $model.form.name, placeholder: "e.g. Keynote at the design meetup",
                         required: true, limit: Limits.nameLength.upperBound, error: model.nameError)
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(label: "Type")
                TypeSelector(selection: $model.form.type)
            }
            Toggle(isOn: $model.form.hasTarget.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Total")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Palette.ink)
                    Text("Optional personal goal, independent from the sum of segments.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
            .tint(Palette.midnight)
            if model.form.hasTarget {
                DurationEditor(label: "Target", seconds: $model.form.targetSeconds, range: Limits.targetTotalSeconds,
                               steps: [60, 300], presets: [300, 600, 900, 1200, 1800, 2700, 3600])
            }
        }
    }

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Segments", trailing: model.segments.isEmpty ? nil : "\(model.segments.count) · \(TimeFormat.clock(model.plannedTotal))")
            if model.draft == nil, let published = model.currentPublished {
                NoticeBanner(
                    text: "\(published.shortName) is published and locked. Any change creates Draft v\(model.nextVersionNumber) — past runs keep \(published.shortName).",
                    systemImage: "lock.fill"
                )
            }
            if model.segments.isEmpty {
                CueCard {
                    Text("No segments yet")
                        .font(Typo.headline)
                        .foregroundColor(Palette.ink)
                    Text("Planned Duration: Not Set Up. Add the first part of your piece — an opening, a story, a closing line.")
                        .font(Typo.callout)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentRow(position: index + 1, segment: segment) {
                            if let id = model.performanceID {
                                router.push(.segmentEditor(performanceID: id, segmentID: segment.id))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    if let id = model.ensureSaved() {
                        router.push(.segmentEditor(performanceID: id, segmentID: nil))
                    }
                } label: {
                    Label("Add Segment", systemImage: "plus")
                }
                .buttonStyle(.cue(.stage))
                if model.segments.count > 1 {
                    Button {
                        showReorder = true
                    } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.cue(.secondary, fullWidth: false))
                }
            }
            totalsSummary
        }
    }

    @ViewBuilder
    private var totalsSummary: some View {
        if !model.segments.isEmpty {
            HStack(spacing: 10) {
                StatTile(label: "Segments add up to", value: TimeFormat.clock(model.plannedTotal))
                if let target = model.form.target {
                    StatTile(
                        label: "Target",
                        value: TimeFormat.clock(target),
                        caption: model.targetGap.map { gap in
                            gap == 0 ? "Plan matches target" : "Plan is \(TimeFormat.delta(gap)) vs target"
                        },
                        tint: (model.targetGap ?? 0) > 0 ? Palette.redInk : Palette.ink
                    )
                }
            }
            if model.plannedTotal > Limits.versionTotalMaxSeconds {
                NoticeBanner(text: "A version can be at most 4:00:00 long to be published.", systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        }
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "This draft")
            CueCard {
                CueTextField(label: "Version Label", text: $model.form.versionLabel, placeholder: "e.g. Shorter intro",
                             limit: Limits.versionLabelMax)
                CueTextEditor(label: "General Note", text: $model.form.generalNote,
                              placeholder: "Anything that applies to the whole piece: venue, props, reminders.",
                              limit: Limits.generalNoteMax, minHeight: 90)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                model.saveDraft()
            } label: {
                Label(model.isNew ? "Save Draft" : (model.isDirty ? "Save Draft" : "Saved"), systemImage: model.isDirty || model.isNew ? "tray.and.arrow.down.fill" : "checkmark")
            }
            .buttonStyle(model.isDirty || model.isNew ? .cuePrimary : .cueSecondary)
            .disabled(!model.isDirty && !model.isNew)

            if model.performanceID != nil {
                Button {
                    if !model.isDirty || model.saveDraft() { showPublish = true }
                } label: {
                    Label(model.draft.map { "Publish Version \($0.number)" } ?? "Publish Version", systemImage: "lock.fill")
                }
                .buttonStyle(.cueStage)
                .disabled(!model.canPublish)

                if !model.canPublish {
                    Text("Nothing to publish — the script matches \(model.currentPublished?.shortName ?? "the published version").")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }

                HStack(spacing: 10) {
                    Button {
                        if let id = model.performanceID { router.push(.rehearsalSetup(RehearsalPreset(performanceID: id))) }
                    } label: {
                        Label("Rehearse", systemImage: "play.circle")
                    }
                    .buttonStyle(.cueSecondary)
                    .disabled(!model.canRehearse)

                    Button {
                        if let id = model.performanceID {
                            router.push(.export(ExportPreset(kind: .cueSheet, performanceID: id, versionID: model.workingVersion?.id)))
                        }
                    } label: {
                        Label("Export Cue Sheet", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.cueSecondary)
                    .disabled(model.segments.isEmpty)
                }
                if model.hasManualRuns, let id = model.performanceID {
                    Button {
                        router.push(.segmentHistory(performanceID: id))
                    } label: {
                        Label("Segment History", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.cueSecondary)
                }
                if !model.canRehearse {
                    Text("Rehearsal needs at least one segment and a published version.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                } else if model.draft != nil {
                    Text("Rehearse uses the published \(model.currentPublished?.shortName ?? "version"). Publish the draft to rehearse its changes.")
                        .font(Typo.caption)
                        .foregroundColor(Palette.muted)
                }
            }
        }
    }
}

// MARK: - Pieces

private struct TypeSelector: View {
    @Binding var selection: PerformanceType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PerformanceType.allCases) { type in
                    Button {
                        selection = type
                    } label: {
                        Label(type.title, systemImage: type.symbol)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(selection == type ? Palette.ink : Palette.blueInk)
                            .padding(.horizontal, 12)
                            .frame(minHeight: Metrics.minTap)
                            .background(
                                Capsule().fill(selection == type ? Palette.spotlight : Palette.blueInk.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == type ? .isSelected : [])
                }
            }
        }
    }
}

struct SegmentRow: View {
    let position: Int
    let segment: Segment
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(position)")
                    .font(Typo.monoHeadline)
                    .foregroundColor(Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.spotlight.opacity(0.55)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(segment.title.isEmpty ? "Untitled segment" : segment.title)
                            .font(Typo.headline)
                            .foregroundColor(Palette.ink)
                            .multilineTextAlignment(.leading)
                        if segment.isOptional { StatusBadge.optional }
                    }
                    if !segment.cueText.trimmed.isEmpty {
                        Text(segment.cueText)
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 6)
                Text(TimeFormat.clock(segment.plannedSeconds))
                    .font(Typo.monoHeadline)
                    .foregroundColor(Palette.ink)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Palette.muted)
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Segment \(position), \(segment.title), planned \(TimeFormat.spoken(segment.plannedSeconds))\(segment.isOptional ? ", optional" : "")")
    }
}

struct PublishDraftSheet: View {
    let versionNumber: Int
    let issues: [ValidationIssue]
    let onCancel: () -> Void
    let onPublish: (String) -> Void
    @State private var changeNote = ""

    var body: some View {
        SheetScaffold(title: "Publish v\(versionNumber)", closeTitle: "Cancel", onClose: onCancel) {
            Text("Publishing freezes this draft. Runs are always tied to the published version they used, and it can never be edited afterwards.")
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if issues.isEmpty {
                NoticeBanner(text: "All segments have a title and a planned time between 0:10 and 1:00:00; the total is within 4 hours.",
                             systemImage: "checkmark.seal.fill")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Fix before publishing")
                    ForEach(issues) { issue in
                        FieldError(text: issue.message)
                    }
                }
            }
            CueTextEditor(label: "Change Note", text: $changeNote, placeholder: "What changed in this version? (optional)",
                          limit: Limits.changeNoteMax, minHeight: 80)
            Button {
                onPublish(changeNote)
            } label: {
                Label("Publish Version \(versionNumber)", systemImage: "lock.fill")
            }
            .buttonStyle(.cuePrimary)
            .disabled(!issues.isEmpty || changeNote.count > Limits.changeNoteMax)
        }
    }
}

/// Drag-to-reorder with a native List in edit mode.
struct ReorderSegmentsSheet: View {
    @State private var order: [Segment]
    let lockedVersionName: String?
    let onSave: ([UUID]) -> Void
    let onCancel: () -> Void

    init(segments: [Segment], lockedVersionName: String?, onSave: @escaping ([UUID]) -> Void, onCancel: @escaping () -> Void) {
        _order = State(initialValue: segments)
        self.lockedVersionName = lockedVersionName
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundColor(Palette.spotlight)
                    .frame(minHeight: Metrics.minTap)
                Spacer()
                Text("Reorder")
                    .font(Typo.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Save") { onSave(order.map(\.id)) }
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Palette.spotlight)
                    .frame(minHeight: Metrics.minTap)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(HeaderBackground())
            if let lockedVersionName {
                NoticeBanner(text: "Saving creates a new draft. \(lockedVersionName) stays as it is.", systemImage: "lock.fill")
                    .padding(Metrics.gutter)
            }
            List {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, segment in
                    HStack {
                        Text("\(index + 1)")
                            .font(Typo.monoHeadline)
                            .foregroundColor(Palette.muted)
                            .frame(width: 30, alignment: .leading)
                        Text(segment.title)
                            .font(Typo.body)
                            .foregroundColor(Palette.ink)
                        Spacer()
                        Text(TimeFormat.clock(segment.plannedSeconds))
                            .font(Typo.mono)
                            .foregroundColor(Palette.muted)
                    }
                    .frame(minHeight: Metrics.minTap)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        }
        .background(Palette.paper.ignoresSafeArea())
    }
}
