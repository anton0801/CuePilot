import SwiftUI

/// Labelled single-line field with character counter and inline error.
struct CueTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var required = false
    var limit: Int? = nil
    var error: String? = nil
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: required, count: limit.map { (text.count, $0) })
            TextField(placeholder, text: $text)
                .font(Typo.body)
                .foregroundColor(Palette.ink)
                .textInputAutocapitalization(capitalization)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(error == nil ? Palette.rule : Palette.redInk.opacity(0.7), lineWidth: 1.5)
                )
                .accessibilityLabel(label + (required ? ", required" : ""))
            if let error {
                FieldError(text: error)
            }
        }
    }
}

/// Multi-line editor (TextEditor, iOS 14+) with counter.
struct CueTextEditor: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var limit: Int? = nil
    var minHeight: CGFloat = 110
    var error: String? = nil
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: false, count: limit.map { (text.count, $0) })
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Typo.body)
                        .foregroundColor(Palette.muted.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(Typo.body)
                    .foregroundColor(Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .frame(minHeight: minHeight)
                    .accessibilityLabel(label)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(error == nil ? Palette.rule : Palette.redInk.opacity(0.7), lineWidth: 1.5)
            )
            if let error {
                FieldError(text: error)
            } else if let hint {
                Text(hint).font(Typo.caption).foregroundColor(Palette.muted)
            }
        }
    }
}

struct FieldLabel: View {
    let label: String
    var required = false
    var count: (Int, Int)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Palette.ink)
            if required {
                Text("Required")
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
            }
            Spacer()
            if let count {
                Text("\(count.0)/\(count.1)")
                    .font(Typo.monoCaption)
                    .foregroundColor(count.0 > count.1 ? Palette.redInk : Palette.muted)
                    .accessibilityLabel("\(count.0) of \(count.1) characters")
            }
        }
    }
}

struct FieldError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(Typo.caption.weight(.semibold))
            .foregroundColor(Palette.redInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Touch-friendly duration control: large readout, ± steps and presets. No keyboard needed.
struct DurationEditor: View {
    let label: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    var steps: [Int] = [10, 60]
    var presets: [Int] = [30, 60, 120, 300]
    var required = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(label: label, required: required)
            HStack(spacing: 8) {
                ForEach(steps.reversed(), id: \.self) { step in
                    stepButton(-step)
                }
                Text(TimeFormat.clock(seconds))
                    .font(Typo.timer(30))
                    .foregroundColor(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                ForEach(steps, id: \.self) { step in
                    stepButton(step)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(TimeFormat.spoken(seconds))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(by: steps.first ?? 10)
                case .decrement: adjust(by: -(steps.first ?? 10))
                @unknown default: break
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets.filter { range.contains($0) }, id: \.self) { preset in
                        Button {
                            seconds = preset
                        } label: {
                            Text(TimeFormat.clock(preset))
                                .font(Typo.monoCaption.weight(.bold))
                                .foregroundColor(seconds == preset ? Palette.ink : Palette.blueInk)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(
                                    Capsule().fill(seconds == preset ? Palette.spotlight : Palette.blueInk.opacity(0.07))
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: Metrics.minTap)
                        .accessibilityLabel("Set \(TimeFormat.spoken(preset))")
                    }
                }
            }
        }
    }

    private func stepButton(_ delta: Int) -> some View {
        Button {
            adjust(by: delta)
        } label: {
            Text(delta > 0 ? "+\(stepText(delta))" : "−\(stepText(-delta))")
                .font(Typo.monoCaption.weight(.bold))
                .foregroundColor(Palette.blueInk)
                .frame(width: 48, height: Metrics.minTap)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.blueInk.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(delta < 0 ? seconds <= range.lowerBound : seconds >= range.upperBound)
    }

    private func stepText(_ value: Int) -> String {
        if value % 3600 == 0 { return "\(value / 3600)h" }
        if value % 60 == 0 { return "\(value / 60)m" }
        return "\(value)s"
    }

    private func adjust(by delta: Int) {
        seconds = min(range.upperBound, max(range.lowerBound, seconds + delta))
    }
}
