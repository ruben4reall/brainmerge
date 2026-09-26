import Foundation
import BrainmergeCore

/// Addresses Brainmerge opens in the browser, and only there: it never connects to them itself.
public enum BrainmergeLinks {
    public static let repository = URL(string: "https://github.com/ruben4reall/brainmerge")!
}

/// One account in the menu bar's menu: the sidebar's word and click, with its name and color.
public struct MenuBarEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tint: Tint
    public let action: SidebarAccountAction
    public let title: String
    public let help: String
    public var isEnabled: Bool { action.isEnabled }
}

/// Everything the menu bar's menu says, from the model's state alone. The view (MenuBarContent) only lays it out.
public enum MenuBarMenu {
    public static let openTitle = "Open Brainmerge"
    public static let settingsTitle = "Settings…"
    public static let starTitle = "Star on GitHub"
    public static let quitTitle = "Quit Brainmerge"
    /// Below the accounts and the RAM line, in this order.
    public static let fixedItems = [openTitle, settingsTitle, starTitle, quitTitle]

    public static let settingTitle = "Show in the menu bar"
    public static let settingFootnote = "Open or show any account from the top right of your screen. With it on, closing this window keeps Brainmerge running there. With it off, closing the window quits Brainmerge, unless the quick opener is on."

    /// The sidebar's rows, in its order. Accounts without a Claude window are left out: the menu opens windows.
    /// `busy` is every account whose app is being worked on (AppModel.accountsBusy), as for the sidebar.
    public static func entries(accounts: [Account], opening: Set<String>, busy: Set<String>, appExists: (String) -> Bool) -> [MenuBarEntry] {
        accounts.compactMap { account in
            let othersOpen = accounts.contains { $0.id != account.id && $0.isRunning }
            let action = SidebarAccountAction.of(account: account, opening: opening, busy: busy, othersOpen: othersOpen, appExists: appExists(account.id))
            guard let title = title(name: account.identity.name, action: action) else { return nil }
            return MenuBarEntry(id: account.id, name: account.identity.name, tint: account.identity.tint, action: action, title: title,
                                help: action.help(for: account, othersOpen: othersOpen))
        }
    }

    /// "Open Work", "Opening Client…": the word first, like Mac menu commands; a waiting word keeps its ellipsis last.
    public static func title(name: String, action: SidebarAccountAction) -> String? {
        guard let label = action.label else { return nil }
        guard label.hasSuffix("…") else { return "\(label) \(name)" }
        return "\(label.dropLast()) \(name)…"
    }

    /// The Mac's RAM in one line, with the Usage screen's figures. Nil when the kernel gave none.
    public static func ramLine(_ mac: MacMemory?) -> String? {
        guard let mac else { return nil }
        let line = "RAM: \(ByteFormat.ram(mac.used)) of \(ByteFormat.capacity(mac.physical)) used (\(ByteFormat.percent(mac.used, of: mac.physical)))"
        switch mac.pressure {
        case .normal: return line
        case .warning: return line + ", running low"
        case .critical: return line + ", very low"
        }
    }

    /// A message waits and no window shows it: the menu says so, and the item opens the window.
    public static func notice(message: UserMessage?, windowOpen: Bool) -> String? {
        guard let message, !windowOpen else { return nil }
        return "\(message.title)…"
    }

    /// Messages only show in the window: an action from the menu that produced a new one brings the window forward.
    public static func revealsWindow(before: UUID?, after: UserMessage?) -> Bool {
        guard let after else { return false }
        return after.id != before
    }

    /// The icon's eyes: open while an account is open or opening, closed otherwise, like the sidebar's creature.
    public static func iconAwake(accounts: [Account], opening: Set<String>) -> Bool {
        !opening.isEmpty || accounts.contains(where: \.isRunning)
    }

    /// What VoiceOver says for the icon.
    public static func iconLabel(openCount: Int) -> String {
        switch openCount {
        case 0: "Brainmerge, no account open"
        case 1: "Brainmerge, 1 account open"
        default: "Brainmerge, \(openCount) accounts open"
        }
    }
}
