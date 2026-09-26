import Foundation
import BrainmergeCore

/// After Claude replaces itself: which windows still run the previous one, and Claude coming back on the first
/// account's folders. Nothing here quits or opens anything without a click.
extension AppModel {
    /// The Claude installed now, when this account's window started before it was updated; nil otherwise.
    public func staleVersion(of slug: String) -> String? {
        staleAccounts.contains(slug) ? claude?.version : nil
    }

    /// The person asked this account to open: a bare Claude that comes up instead is said after 10 s.
    func requestedOpen(_ slug: String) { updateWatch.requestedOpen(slug, at: now()) }

    /// Called at the end of every reload with its snapshot: feeds UpdateWatch and says what it found. True when
    /// something shown changed.
    @discardableResult
    func watchUpdates(snapshot: ProcessMonitor.Snapshot) -> Bool {
        guard let claude else { return false }
        let windows = accounts.map { account in
            let main = account.isRunning
                ? snapshot.mains.first { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) } : nil
            return UpdateWatch.Window(slug: account.id, isPrimary: account.identity.isPrimary, running: account.isRunning,
                                      startAbstime: main?.startAbstime, isCopy: account.claudeVersion != .notApplicable)
        }
        // The bundle's Info.plist changed when Claude was replaced: read only on the reload that sees a new version.
        let plist = claude.url.appending(path: "Contents/Info.plist").path
        let events = updateWatch.observe(version: claude.version, windows: windows, now: now(), abstime: abstimeNow(),
                                         ticksPerSecond: ticksPerSecond,
                                         bundleModified: { try? FileManager.default.attributesOfItem(atPath: plist)[.modificationDate] as? Date })
        let changed = updateWatch.stale != staleAccounts
        if changed { staleAccounts = updateWatch.stale }
        guard let primary = accounts.first(where: \.identity.isPrimary)?.identity.name else { return changed }
        for event in events {
            switch event {
            case .bareRelaunch(let slug):
                let w = name(of: slug)
                message = UserMessage(title: "Claude restarted itself to update and came back as \(primary), not \(w).",
                                      detail: "Nothing was changed.", action: .reopenInstead(slug: slug),
                                      actionLabel: "Reopen \(w)", cancelLabel: "Keep \(primary)")
            case .openedElsewhere(let slug):
                message = UserMessage(title: "Claude opened on \(primary)'s folders, not \(name(of: slug))'s.", detail: "Nothing was changed.")
            }
        }
        return changed
    }

    /// Whether this account's window runs now, asked of `ps` again (not the last reload).
    nonisolated static func isRunning(_ identity: Identity, manager: IdentityManager, paths: Paths, claude: ClaudeApp) -> Bool {
        (try? manager.monitor.isRunning(identity: identity, paths: paths, claude: claude)) ?? false
    }

    /// A clean quit of an account's window, the SIGTERM Quit sends (a fake in tests, which never signal).
    func quitWindow(_ identity: Identity) {
        if let quitAccount { quitAccount(identity) } else { try? manager.quit(identity) }
    }

    /// Opens an account through its own app, marked as opening (a fake in tests, which never start a process).
    func launchWindow(_ slug: String) {
        if let launchAccount { launchAccount(slug); return }
        do { try manager.launch(slug: slug); markOpening(slug) } catch { present(error) }
    }

    /// Quits `identity`'s window, waits for it to exit (10 s at most), then opens `slug`. False when it did not exit.
    private func quitThenOpen(quitting identity: Identity, opening slug: String, claude: ClaudeApp) async -> Bool {
        let manager = self.manager, paths = self.paths
        return await UpdateWatch.restart(
            quit: { @MainActor [weak self] in self?.quitWindow(identity) },
            isRunning: { Self.isRunning(identity, manager: manager, paths: paths, claude: claude) },
            launch: { @MainActor [weak self] in self?.launchWindow(slug) },
            pause: { try? await Task.sleep(for: $0) })
    }

    /// Quits the account's window (SIGTERM), waits for it to exit, then opens it again on the Claude installed now.
    /// A second click while it runs does nothing: the window is never opened twice.
    public func restart(_ slug: String) async {
        guard !restarting.contains(slug), let account = accounts.first(where: { $0.id == slug }), let claude else { return }
        restarting.insert(slug)
        defer { restarting.remove(slug) }
        if !(await quitThenOpen(quitting: account.identity, opening: slug, claude: claude)) {
            message = UserMessage(title: "\(account.identity.name) is still open", detail: "Its window did not close. Nothing was opened again.")
        }
        reload()
    }

    /// Restarts once no Claude Code session runs under the account's window. Stops waiting if the window closes, or
    /// if another window took its place (quit and reopened by hand: that one already runs the Claude installed now).
    public func restartWhenIdle(_ slug: String) {
        guard !restartingWhenIdle.contains(slug) else { return }
        restartingWhenIdle.insert(slug)
        Task {
            defer { restartingWhenIdle.remove(slug) }
            var clicked: Int32?
            while true {
                guard let account = accounts.first(where: { $0.id == slug }), account.isRunning, let claude else { return }
                let snapshot = (try? manager.monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
                guard let main = snapshot.mains.first(where: { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) }),
                      main.pid == (clicked ?? main.pid)
                else { return }
                clicked = main.pid
                if !snapshot.hasClaudeCode(under: main.pid) { await restart(slug); return }
                try? await Task.sleep(for: idlePoll)
            }
        }
    }

    /// "Reopen Work": quits the bare Claude gracefully, waits for it to exit, then opens Work through its launcher.
    public func reopenInstead(_ slug: String) async {
        guard !restarting.contains(slug), let primary = accounts.first(where: \.identity.isPrimary), let claude else { return }
        restarting.insert(slug)
        defer { restarting.remove(slug) }
        if !(await quitThenOpen(quitting: primary.identity, opening: slug, claude: claude)) {
            message = UserMessage(title: "\(primary.identity.name) is still open", detail: "Claude did not close. Nothing was opened.")
        }
        reload()
    }
}
