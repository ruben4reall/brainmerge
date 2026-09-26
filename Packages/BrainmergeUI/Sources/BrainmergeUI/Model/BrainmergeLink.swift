import Foundation
import BrainmergeCore

/// brainmerge:// links, for Raycast, Stream Deck or a note. Any web page can fire a URL, so a link can only open or
/// show: never add, edit, remove, quit, change a memory or pass a folder.
public enum BrainmergeLink {
    public enum Action: Equatable, Sendable {
        case open(String)
        case show(String)
        /// The Memory screen, on the named memory when it exists.
        case memory(String?)
        case usage
        case settings
    }

    public static let scheme = "brainmerge"
    static let verbs = ["open", "show", "memory", "usage", "settings"]

    /// The action, or nil for anything else. The account must exist; queries and extra path parts are ignored.
    public static func parse(_ url: URL, accounts: Set<String>) -> Action? {
        guard url.scheme?.lowercased() == scheme, let verb = url.host(percentEncoded: false)?.lowercased() else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        let first = parts.first
        switch verb {
        case "open", "show":
            guard let slug = first, isSlug(slug), accounts.contains(slug) else { return nil }
            return verb == "open" ? .open(slug) : .show(slug)
        case "memory":
            guard let id = first else { return .memory(nil) }
            return isSlug(id) ? .memory(id) : nil
        case "usage": return .usage
        case "settings": return .settings
        default: return nil
        }
    }

    /// The IdentitySlug rules: what make(from:) would give back unchanged. Rejects "..", "/", escapes and capitals.
    static func isSlug(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 32 && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            && IdentitySlug.make(from: s) == s
    }

    /// The same link twice within 2 s (a double click in a launcher) acts once.
    public struct Gate: Sendable {
        var last: (url: URL, at: Date)?
        public init() {}
        public mutating func admit(_ url: URL, at now: Date = Date()) -> Bool {
            if let last, last.url == url, now.timeIntervalSince(last.at) < 2 { return false }
            last = (url, now)
            return true
        }
    }
}

/// One account in the Accounts menu: the cards' word, and Cmd-Option-1 to 9 for the first nine.
public struct AccountsMenuItem: Identifiable, Equatable, Sendable {
    public let entry: MenuBarEntry
    public let shortcut: Character?
    public var id: String { entry.id }
    public var title: String { entry.title }
}

public enum AccountsMenu {
    public static let addTitle = "Add Account…"
    public static let quitAllTitle = "Quit All Accounts…"

    public static func items(accounts: [Account], opening: Set<String>, busy: Set<String>, appExists: (String) -> Bool) -> [AccountsMenuItem] {
        MenuBarMenu.entries(accounts: accounts, opening: opening, busy: busy, appExists: appExists).enumerated().map { index, entry in
            AccountsMenuItem(entry: entry, shortcut: index < 9 ? Character(String(index + 1)) : nil)
        }
    }

    public static func quitAllTitle(windows: Int) -> String {
        "Quit \(windows) Claude window\(windows == 1 ? "" : "s")?"
    }

    public static func quitAllDetail(sessions: Int) -> String? {
        sessions > 0 ? "Claude Code sessions running in them stop too." : nil
    }
}
