import BrainmergeCore

/// What a click on an account in the sidebar does, and the word shown next to its name. One function decides both,
/// from local state only (running, opening, busy, app on disk), so the word never promises what the click will not do.
/// The words are the cards' words: "Open" launches, "Show" brings a running window forward. Never "Update": the
/// sidebar click does not update anything.
public enum SidebarAccountAction: Equatable, Sendable {
    /// Launches Claude as this account.
    case open
    /// Brings this account's running Claude window forward.
    case show
    /// A launch is on its way: a second click would start a second instance.
    case opening
    /// Its app is being rebuilt, updated or removed: opening it now would open a half-built app.
    case updating
    /// The app of a secondary account is missing on disk: the click rebuilds it instead of failing.
    case rebuild
    /// A Claude Code only account: there is no Claude window to open.
    case none

    /// In this order: an account without a Claude window, work on its app, a window already running, a launch on
    /// its way, a missing app, and only then "Open". `busy` is every account whose app is being touched right now.
    public static func of(account: Account, opening: Set<String>, busy: Set<String>, othersOpen: Bool, appExists: Bool) -> SidebarAccountAction {
        let identity = account.identity
        if !identity.surfaces.desktop { return .none }
        if busy.contains(account.id) { return .updating }
        if account.isRunning { return .show }
        if opening.contains(account.id) { return .opening }
        if !identity.isPrimary, !appExists { return .rebuild }
        return .open
    }

    /// The word next to the name, nil when there is nothing to do.
    public var label: String? {
        switch self {
        case .open: "Open"
        case .show: "Show"
        case .opening: "Opening…"
        case .updating: "Updating…"
        case .rebuild: "Rebuild"
        case .none: nil
        }
    }

    /// A click does something only when the label promises it. A Claude Code only account stays clickable:
    /// the click says why there is no window.
    public var isEnabled: Bool { self != .opening && self != .updating }

    /// The tooltip and the VoiceOver hint: what the click does, in one plain sentence.
    public func help(for account: Account, othersOpen: Bool) -> String {
        let name = account.identity.name
        switch self {
        case .open:
            // Logging in while another Claude runs: the browser's login link lands in the window already open.
            // Say so, and never offer to quit the others from here (one of them may be the primary Claude).
            if account.needsLogin, othersOpen {
                return "Opens Claude to log in. Quit your other Claude windows first, so the login lands in this one."
            }
            // The email Claude Code uses, when known: it tells two accounts with similar names apart.
            let email = account.codeAccount.map { " (\($0.email))" } ?? ""
            return Self.withVersion("Open Claude as \(name)\(email)", account)
        case .show: return Self.withVersion("Show \(name)'s Claude window", account)
        case .opening: return "Opening \(name)…"
        case .updating: return "Brainmerge is working on \(name)'s app. Try again in a moment."
        case .rebuild: return "\(name)'s app is missing. Click to build it again."
        case .none: return "Claude Code only: this account has no Claude window"
        }
    }

    /// VoiceOver reads the name, then the word next to it.
    public func accessibilityLabel(for account: Account) -> String {
        label.map { "\(account.identity.name), \($0)" } ?? account.identity.name
    }

    /// An outdated tinted copy still opens; the tooltip says which Claude it was built for.
    static func withVersion(_ sentence: String, _ account: Account) -> String {
        guard case .outdated(let installed, let built) = account.claudeVersion else { return sentence }
        return "\(sentence). Built for Claude \(built), \(installed) is installed."
    }
}
