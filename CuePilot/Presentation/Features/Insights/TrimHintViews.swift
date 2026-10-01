import SwiftUI

/// Wording for a trim hint, shared by the full card and the compact Home row.
enum TrimHintText {
    static func headline(_ hint: TrimHint) -> String {
        switch (hint.reference, hint.isOver) {
        case let (.target(target), true):
            return "\(TimeFormat.clock(hint.gap)) over your \(TimeFormat.clock(target)) target"
        case (.plan, true):
            return "\(TimeFormat.clock(hint.gap)) over plan"
        case let (.target(target), false):
            return hint.gap == 0 ? "Exactly on your \(TimeFormat.clock(target)) target"
                : "Within your \(TimeFormat.clock(target)) target · \(TimeFormat.clock(-hint.gap)) to spare"
        case (.plan, false):
            return hint.gap == 0 ? "Exactly on plan" : "Under plan · \(TimeFormat.clock(-hint.gap)) to spare"
        }
    }

    static func overrunList(_ hint: TrimHint, limit: Int = 2) -> String? {
        let items = hint.overruns.prefix(limit).map { "\($0.title) \(TimeFormat.delta($0.over))" }
        guard !items.isEmpty else { return nil }
        return (hint.overruns.count == 1 ? "Over its plan: " : "Biggest overruns: ") + items.joined(separator: ", ")
    }

    static func source(_ hint: TrimHint) -> String {
        "Run of \(DateText.short(hint.run.startedAt)) · \(TimeFormat.clock(hint.actualTotal)) · v\(hint.run.snapshot.versionNumber)"
    }
}

/// "Where to trim" — arithmetic on one complete Manual Next run. Never rates the performance.
struct TrimHintCard: View {
    let hint: TrimHint
    var showsSource = true

    var body: some View {
        CueCard(accent: hint.isOver ? Palette.stageRed : Palette.midnightLift) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "scissors").font(Typo.eyebrow)
                    // Text-level tracking: the View modifier needs iOS 16.
                    Text("WHERE TO TRIM").font(Typo.eyebrow).tracking(1)
                }
                .foregroundColor(Palette.redInk)
                Spacer()
                if showsSource {
                    Text(TrimHintText.source(hint))
                        .font(Typo.monoCaption)
                        .foregroundColor(Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Text(TrimHintText.headline(hint))
                .font(Typo.title)
                .foregroundColor(hint.isOver ? Palette.redInk : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !hint.topOverruns.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(hint.topOverruns.enumerated()), id: \.element.id) { index, overrun in
                        overrunRow(index: index + 1, overrun)
                    }
                }
            }

            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(Typo.callout)
                    .foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Simple arithmetic on a complete Manual Next run: actual minus plan, segment by segment.")
                .font(Typo.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func overrunRow(index: Int, _ overrun: TrimHint.Overrun) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(Palette.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Palette.spotlight.opacity(0.55)))
            VStack(alignment: .leading, spacing: 2) {
                Text(overrun.title)
                    .font(Typo.headline)
                    .foregroundColor(Palette.ink)
                    .lineLimit(2)
                Text("plan \(TimeFormat.clock(overrun.planned)) → ran \(TimeFormat.clock(overrun.actual))")
                    .font(Typo.monoCaption)
                    .foregroundColor(Palette.muted)
            }
            Spacer(minLength: 6)
            DeviationLabel(seconds: overrun.over, compact: true)
        }
    }

    private var notes: [String] {
        var notes: [String] = []
        let count = hint.topOverruns.count
        if hint.isOver {
            if count > 0 {
                let subject = count == 1 ? "this segment saves" : "these \(count) save"
                let tail = hint.remainingAfterTop == 0
                    ? "That covers the whole \(TimeFormat.clock(hint.gap))."
                    : "\(TimeFormat.clock(hint.remainingAfterTop)) would still be over — the plan itself needs trimming too."
                notes.append("Back to plan, \(subject) \(TimeFormat.clock(hint.topSavings)). \(tail)")
            } else {
                notes.append("No segment ran over its own plan — the plan itself is longer than the target.")
            }
        } else if count > 0 {
            notes.append("Still over their own plan in this run — worth a look even though the total fits.")
        }
        if let planOver = hint.planOverTarget {
            notes.append("Even run exactly to plan, the current script is \(TimeFormat.clock(planOver)) over the target.")
        }
        if !hint.skippedOptionalTitles.isEmpty {
            notes.append("Skipped in this run (not in the total): " + hint.skippedOptionalTitles.joined(separator: ", ") + ".")
        }
        return notes
    }
}

/// One-line version for Home.
struct TrimHintSummaryRow: View {
    let hint: TrimHint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "scissors")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Palette.redInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.stageRed.opacity(0.1)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(TrimHintText.headline(hint))
                        .font(Typo.headline)
                        .foregroundColor(hint.isOver ? Palette.redInk : Palette.ink)
                        .multilineTextAlignment(.leading)
                    if let list = TrimHintText.overrunList(hint) {
                        Text(list)
                            .font(Typo.caption)
                            .foregroundColor(Palette.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Palette.muted)
                    .padding(.top, 8)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.stageRed.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.redInk.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Segment History")
    }
}
