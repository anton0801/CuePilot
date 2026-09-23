import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI into the Domain.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        let shift = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moving, at: Swift.min(Swift.max(0, destination - shift), count))
    }
}

/// Plain-text time formatting shared by the UI and exports.
enum TimeFormat {
    /// `m:ss`, or `h:mm:ss` from one hour. Truncates toward zero so a live clock never runs ahead.
    static func clock(_ seconds: Double) -> String {
        clock(Int(max(0, seconds).rounded(.down)))
    }

    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// `+0:12`, `−0:05` or `±0:00`. Uses a real minus sign so the column aligns in monospaced text.
    static func delta(_ seconds: Int) -> String {
        if seconds == 0 { return "±0:00" }
        let sign = seconds > 0 ? "+" : "−"
        return sign + clock(abs(seconds))
    }

    /// Human sentence form: "2 min 30 s".
    static func spoken(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs) s") }
        return parts.joined(separator: " ")
    }

    /// Whole seconds used for completed-segment maths, so the actual, the plan and the
    /// deviation shown side by side always add up.
    static func wholeSeconds(_ seconds: Double) -> Int {
        Int(max(0, seconds).rounded())
    }
}

enum DateText {
    static func short(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
