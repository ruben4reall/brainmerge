import Foundation
import BrainmergeCore

/// After Claude replaces itself: which windows still run the previous one, and Claude coming back on the first
/// account's folders. Nothing here quits or opens anything without a click.
extension AppModel {
    /// The person asked this account to open: a bare Claude that comes up instead is said after 10 s.
    func requestedOpen(_ slug: String) { openRequests[slug] = now() }

    /// Called at the end of every reload with its snapshot. True when something shown changed.
    @discardableResult
    func watchUpdates(snapshot: ProcessMonitor.Snapshot) -> Bool {
        guard let claude else { return false }
        let date = now()
        if let seen = seenClaudeVersion, seen != claude.version {
            let plist = claude.url.appending(path: "Contents/Info.plist")
            let modified = (try? FileManager.default.attributesOfItem(atPath: plist.path)[.modificationDate] as? Date) ?? date
            claudeChange = UpdateWatch.Change(version: claude.version, observedAbstime: abstimeNow(), observedAt: date, bundleModified: modified)
        }
        seenClaudeVersion = claude.version

        var stale: Set<String> = []
        for account in accounts where account.isRunning {
            let main = snapshot.mains.first { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) }
            if UpdateWatch.isStale(startAbstime: main?.startAbstime, change: claudeChange, ticksPerSecond: ticksPerSecond) { stale.insert(account.id) }
        }
        let changed = stale != staleAccounts
        if changed { staleAccounts = stale }

        let running = Set(accounts.filter(\.isRunning).map(\.id))
        defer { runningBefore = running }
        guard let before = runningBefore, let primary = accounts.first(where: \.identity.isPrimary) else { return changed }
        let secondaries = Set(accounts.filter { !$0.identity.isPrimary }.map(\.id))
        if let exited = before.subtracting(running).intersection(secondaries).first { lastSecondaryExit = (exited, date) }
        let primaryAppeared = running.contains(primary.id) && !before.contains(primary.id)
        if primaryAppeared {
            primaryAppearedAt = date
            // A version change counts while it is recent: Claude replaces itself, then comes back within a minute.
            let versionChanged = claudeChange.map { date.timeIntervalSince($0.observedAt) <= 300 } ?? false
            let deliberate = openRequests[primary.id] != nil
            if let exit = lastSecondaryExit, let target = accounts.first(where: { $0.id == exit.slug }),
               UpdateWatch.isBareRelaunch(now: date, lastSecondaryExit: exit.at, primaryWasRunning: false,
                                          versionChanged: versionChanged, primaryOpenedByPerson: deliberate) {
                lastSecondaryExit = nil
                let p = primary.identity.name, w = target.identity.name
                message = UserMessage(title: "Claude restarted itself to update and came back as \(p), not \(w).",
                                      detail: "Nothing was changed.", action: .reopenInstead(slug: target.id),
                                      actionLabel: "Reopen \(w)", cancelLabel: "Keep \(p)")
            }
        }
        if !running.contains(primary.id) { primaryAppearedAt = nil }

        for (slug, since) in openRequests {
            guard let target = accounts.first(where: { $0.id == slug }) else { openRequests[slug] = nil; continue }
            if running.contains(slug) || date.timeIntervalSince(since) > 60 { openRequests[slug] = nil; continue }
            guard !target.identity.isPrimary else { continue }
            let bare = primaryAppearedAt.map { $0 >= since } ?? false
            if UpdateWatch.openedElsewhere(since: since, now: date, targetRunning: false, bareAppeared: bare) {
                openRequests[slug] = nil
                message = UserMessage(title: "Claude opened on \(primary.identity.name)'s folders, not \(target.identity.name)'s.",
                                      detail: "Nothing was changed.")
            }
        }
        return changed
    }

    /// Whether this account's window runs now, asked of `ps` again (not the last reload).
    nonisolated static func isRunning(_ identity: Identity, manager: IdentityManager, paths: Paths, claude: ClaudeApp) -> Bool {
        (try? manager.monitor.isRunning(identity: identity, paths: paths, claude: claude)) ?? false
    }

    /// Quits the account's window (SIGTERM), waits for it to exit, then opens it again on the Claude installed now.
    public func restart(_ slug: String) async {
        guard let account = accounts.first(where: { $0.id == slug }), let claude else { return }
        let manager = self.manager, paths = self.paths, identity = account.identity
        let done = await UpdateWatch.restart(
            quit: { try? manager.quit(identity) },
            isRunning: { Self.isRunning(identity, manager: manager, paths: paths, claude: claude) },
            launch: { @MainActor [weak self] in self?.relaunch(slug) },
            pause: { try? await Task.sleep(for: $0) })
        if !done {
            message = UserMessage(title: "\(identity.name) is still open", detail: "Its window did not close. Nothing was opened again.")
        }
        reload()
    }

    private func relaunch(_ slug: String) {
        do { try manager.launch(slug: slug); markOpening(slug) } catch { present(error) }
    }

    /// Restarts once no Claude Code session runs under the account's window. Stops waiting if the window closes.
    public func restartWhenIdle(_ slug: String) {
        guard !restartingWhenIdle.contains(slug) else { return }
        restartingWhenIdle.insert(slug)
        Task {
            defer { restartingWhenIdle.remove(slug) }
            while true {
                guard let account = accounts.first(where: { $0.id == slug }), account.isRunning, let claude else { return }
                let snapshot = (try? manager.monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
                guard let main = snapshot.mains.first(where: { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) })
                else { return }
                if !snapshot.hasClaudeCode(under: main.pid) { await restart(slug); return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// "Reopen Work": quits the bare Claude gracefully, waits for it to exit, then opens Work through its launcher.
    public func reopenInstead(_ slug: String) async {
        guard let primary = accounts.first(where: \.identity.isPrimary), let claude else { return }
        let manager = self.manager, paths = self.paths, identity = primary.identity
        let done = await UpdateWatch.restart(
            quit: { try? manager.quit(identity) },
            isRunning: { Self.isRunning(identity, manager: manager, paths: paths, claude: claude) },
            launch: { @MainActor [weak self] in self?.relaunch(slug) },
            pause: { try? await Task.sleep(for: $0) })
        if !done { message = UserMessage(title: "\(identity.name) is still open", detail: "Claude did not close. Nothing was opened.") }
        reload()
    }
}
