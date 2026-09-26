import AppKit
import Foundation
import BrainmergeCore

/// One account in the quick opener: its photo or color, its name, its note and the sidebar's word. The note only, never
/// the email Claude Code records: the panel shows over any app, a shared screen included.
public struct QuickOpenerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let note: String?
    public let tint: Tint
    /// What Return does, decided by the sidebar's own rule (see SidebarAccountAction).
    public let action: SidebarAccountAction

    public init(id: String, name: String, note: String?, tint: Tint, action: SidebarAccountAction) {
        self.id = id; self.name = name; self.note = note; self.tint = tint; self.action = action
    }

    /// The sidebar's word; a Claude Code only account says so, as on its card.
    public var word: String? { action.label ?? (action == .none ? "Claude Code only" : nil) }
    public var isEnabled: Bool { action.isEnabled }
}

/// What the quick opener lists, in which order, and which row is picked.
public enum QuickOpenerRanking {
    /// Every account in the sidebar's order, Claude Code only ones included: Cmd-Return and Cmd-U work for them too.
    public static func rows(accounts: [Account], opening: Set<String>, busy: Set<String>, appExists: (String) -> Bool) -> [QuickOpenerRow] {
        accounts.map { account in
            let othersOpen = accounts.contains { $0.id != account.id && $0.isRunning }
            let action = SidebarAccountAction.of(account: account, opening: opening, busy: busy, othersOpen: othersOpen, appExists: appExists(account.id))
            return QuickOpenerRow(id: account.id, name: account.identity.name, note: account.identity.note, tint: account.identity.tint, action: action)
        }
    }

    /// The rows that match, the name's start first, then the start of a word in the name, then the note. Within each,
    /// the sidebar's order stays. Case and accents do not count; an empty query keeps every row.
    public static func filter(_ rows: [QuickOpenerRow], query: String) -> [QuickOpenerRow] {
        let query = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return rows }
        let ranked = rows.compactMap { row in rank(name: row.name, note: row.note, query: query).map { (row, $0) } }
        // A stable sort: enumerated offsets break ties in the sidebar's order.
        return ranked.enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }.map(\.element.0)
    }

    /// 0 for the name's start, 1 for a word's start in the name, 2 for the note, nil for no match. `query` is folded.
    static func rank(name: String, note: String?, query: String) -> Int? {
        let name = fold(name)
        if name.hasPrefix(query) { return 0 }
        let starts = name.indices.filter { index in
            index != name.startIndex && !isWordCharacter(name[name.index(before: index)]) && isWordCharacter(name[index])
        }
        if starts.contains(where: { name[$0...].hasPrefix(query) }) { return 1 }
        if let note, fold(note).contains(query) { return 2 }
        return nil
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// The arrows move the pick within the rows, never past either end. A pick left past the end by a shorter list
    /// counts as the last row.
    public static func moved(_ selection: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return clamped(clamped(selection, count: count) + step, count: count)
    }

    /// The row a pick stands for in a list of `count` rows.
    public static func clamped(_ selection: Int, count: Int) -> Int { count > 0 ? min(max(selection, 0), count - 1) : 0 }
}

/// What a key does in the quick opener.
public enum QuickOpenerCommand: Equatable, Sendable { case open, memory, usage, close, next, previous }

public enum QuickOpenerKeys {
    static let returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53, down: UInt16 = 125, up: UInt16 = 126

    /// Return opens or shows, Cmd-Return opens the memory, Cmd-U the usage, Esc closes, the arrows move. Nil leaves
    /// the key to the search field. U is read by its letter, not its place on the keyboard.
    public static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> QuickOpenerCommand? {
        let held = modifiers.intersection([.command, .control, .option, .shift])
        switch keyCode {
        case escape: return .close
        case returnKey, enter: return held.isEmpty ? .open : held == .command ? .memory : nil
        case down: return held.isEmpty ? .next : nil
        case up: return held.isEmpty ? .previous : nil
        default: return held == .command && characters?.lowercased() == "u" ? .usage : nil
        }
    }
}
