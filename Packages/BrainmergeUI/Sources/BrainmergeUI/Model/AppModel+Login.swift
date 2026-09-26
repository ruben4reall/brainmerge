import Foundation
import BrainmergeCore

/// "Log in to …": closes the other Claude windows, opens the account, and reopens the others on a click only.
extension AppModel {
    public func beginLogin(_ slug: String) {
        guard let target = accounts.first(where: { $0.id == slug }), target.identity.surfaces.desktop else { return }
        let snapshot = (try? manager.monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
        var sessions: [String: Int] = [:]
        if let claude {
            for account in openAccounts {
                if let main = snapshot.mains.first(where: { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) }) {
                    sessions[account.id] = snapshot.claudeCodeSessions(under: main.pid)
                }
            }
        }
        let member = { (a: Account) in LoginFlow.Member(slug: a.id, name: a.identity.name) }
        login = LoginFlow(target: member(target), running: openAccounts.map(member), codeSessions: sessions,
                          connectedAtStart: target.hasSession)
    }

    /// The add sheet has gone: the account it added and that must log in gets its Log in sheet, once.
    public func beginPendingLogin() {
        guard let slug = pendingLogin else { return }
        pendingLogin = nil
        beginLogin(slug)
    }

    public func startLogin() { run(login.map { var f = $0; defer { login = f }; return f.start() } ?? []) }

    public func confirmLoggedIn() { login?.confirmLoggedIn() }

    public func reopenAfterLogin() {
        guard var flow = login else { return }
        let effects = flow.reopen()
        guard !effects.isEmpty else { return }
        login = nil
        run(effects)
    }

    public func cancelLogin() {
        guard var flow = login else { return }
        login = nil
        run(flow.cancel())
    }

    /// Follows the flow on each reload: the exits it waits for, then the target's session. A window Cancel asked back
    /// while it was still closing opens once it has exited, within 30 s: one quit by hand later stays closed.
    func advanceLogin() -> Bool {
        let running = Set(openAccounts.map(\.id))
        for (slug, since) in reopenOnceClosed.sorted(by: { $0.key < $1.key }) {
            if now().timeIntervalSince(since) > 30 { reopenOnceClosed[slug] = nil; continue }
            if !running.contains(slug) { reopenOnceClosed[slug] = nil; launchWindow(slug) }
        }
        guard var flow = login else { return false }
        let connected = accounts.first { $0.id == flow.target.slug }?.hasSession ?? false
        let effects = flow.observe(running: running, connected: connected)
        let changed = flow != login
        login = flow
        run(effects)
        return changed
    }

    private func run(_ effects: [LoginFlow.Effect]) {
        for effect in effects {
            switch effect {
            case .quit(let slug):
                guard let a = accounts.first(where: { $0.id == slug }) else { continue }
                quitWindow(a.identity)
            case .open(let slug):
                launchWindow(slug)
            case .openOnceClosed(let slug):
                reopenOnceClosed[slug] = now()
            }
        }
    }
}
