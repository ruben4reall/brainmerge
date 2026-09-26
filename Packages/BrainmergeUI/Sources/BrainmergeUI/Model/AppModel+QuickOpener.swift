import Foundation
import BrainmergeCore

/// The quick opener's rows and what its keys do (see QuickOpenerPanel). Every action goes through a path the window
/// already has: it never changes which account a window is logged into.
extension AppModel {
    /// Every account in the sidebar's order, with the sidebar's word.
    public var quickOpenerRows: [QuickOpenerRow] {
        QuickOpenerRanking.rows(accounts: accounts, opening: opening, busy: accountsBusy, appExists: { appURL(of: $0) != nil })
    }

    /// Return opens or shows (the Accounts menu's click, with its Log in guard), Cmd-Return opens the account's memory
    /// in the notes app of Settings, Cmd-U shows the Usage screen at its card. An account that is gone does nothing.
    @discardableResult
    public func quickOpen(_ command: QuickOpenerCommand, on slug: String) -> Task<Void, Never>? {
        guard let account = accounts.first(where: { $0.id == slug }) else { return nil }
        switch command {
        case .open: return openFromMenu(slug)
        case .memory: openMemory(of: account)
        case .usage:
            requestedUsage = slug
            requestedScreen = .usage
            windowRequests += 1
        case .close, .next, .previous: break
        }
        return nil
    }

    /// The memory the account writes to, in the notes app. A folder moved away is said in the window, with the way to
    /// Health, instead of a click that does nothing.
    func openMemory(of account: Account) {
        guard let folder = brain(of: account.identity) else { return }
        guard FileManager.default.fileExists(atPath: folder.url.path) else {
            let home = paths.home.path
            let place = folder.path.hasPrefix(home + "/") ? "~" + folder.path.dropFirst(home.count) : folder.path
            message = UserMessage(title: "The \(folder.name) memory is not where it was",
                                  detail: "Its folder is gone from \(place). Settings, Health, can point Brainmerge at where it is now.",
                                  action: .openSettings, actionLabel: "Open Settings")
            windowRequests += 1
            return
        }
        openInNotes(folder.url, notesApp)
    }
}
