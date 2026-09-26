import Foundation
import BrainmergeCore

extension AppModel {
    /// A brainmerge:// link. On a cold launch it waits for the first screen. Anything that does not parse does nothing.
    public func handle(_ url: URL) {
        guard linkGate.admit(url) else { return }
        guard launchPhase == .ready else {
            runBeforeReady { [weak self] in self?.act(on: url) }
            return
        }
        act(on: url)
    }

    private func act(on url: URL) {
        guard let action = BrainmergeLink.parse(url, accounts: Set(accounts.map(\.id))) else { return }
        switch action {
        case .open(let slug), .show(let slug): openFromMenu(slug)
        case .memory(let id):
            if let id, brains.contains(where: { $0.id == id }) { selectBrain(id) }
            requestedScreen = .memory
            windowRequests += 1
        case .usage: requestedScreen = .usage; windowRequests += 1
        case .settings: requestedScreen = .settings; windowRequests += 1
        }
    }

    /// The Accounts menu and links: an account that still has to log in, with other Claude windows open, goes
    /// through the Log in sheet, which closes the others first. Both can come with the window closed: the sheet, or a
    /// message the click produced, asks for it (see `windowRequests`).
    @discardableResult
    public func openFromMenu(_ slug: String) -> Task<Void, Never>? {
        guard let account = accounts.first(where: { $0.id == slug }) else { return nil }
        if account.needsLogin, !account.isRunning, openAccounts.contains(where: { $0.id != slug }) {
            requestedScreen = .accounts
            beginLogin(slug)
            windowRequests += 1
            return nil
        }
        return Task {
            let before = message?.id
            await perform(menuEntries.first { $0.id == slug }?.action ?? .open, on: slug)
            if MenuBarMenu.revealsWindow(before: before, after: message) { windowRequests += 1 }
        }
    }

    /// Open Claude windows, and the Claude Code sessions running in them, for the quit confirmation.
    public func quitAllCounts() -> (windows: Int, sessions: Int) {
        let open = openAccounts
        guard let claude, !open.isEmpty else { return (open.count, 0) }
        let snapshot = (try? manager.monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
        let sessions = open.reduce(0) { sum, account in
            guard let main = snapshot.mains.first(where: { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) })
            else { return sum }
            return sum + snapshot.claudeCodeSessions(under: main.pid)
        }
        return (open.count, sessions)
    }

    /// Quits every open account's Claude window. Brainmerge itself stays.
    public func quitAll() { for account in openAccounts { quit(account.id) } }
}
