import Foundation
import BrainmergeCore

/// The words of "Check limits" on the Usage screen: Claude Code's own labels and reset times, as it printed them.
enum LimitsText {
    static let caption = "Limits come from Claude Code for this account, the same as typing /usage. Brainmerge asks only when you click."
    static let checking = "Asking Claude Code…"

    /// A card with two accounts (a shared history) names whose limits each block shows.
    static func title(name: String, shared: Bool) -> String { shared ? "Limits for \(name)" : "Limits" }

    /// "42%", "12.5%": a point whatever the Mac's language.
    static func percent(_ line: LimitLine) -> String {
        let rounded = (line.percent * 10).rounded() / 10
        return (rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)) + "%"
    }

    static func resets(_ line: LimitLine) -> String? { line.resets.map { "Resets \($0)" } }

    static func accessibilityLabel(_ line: LimitLine) -> String {
        "\(line.label): \(percent(line)) used" + (line.resets.map { ", resets \($0)" } ?? "")
    }

    static func checkedAt(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "Checked at \(formatter.string(from: date))"
    }
}
