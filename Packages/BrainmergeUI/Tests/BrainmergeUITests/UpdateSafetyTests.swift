import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// A Claude update seen by the app: windows started before it, and Claude coming back on the first account's folders.
@MainActor @Suite struct UpdateSafetyTests {
    final class Box: @unchecked Sendable { var ps = ""; var starts: [Int32: UInt64] = [:] }

    func model(_ e: ManagerEnv, _ box: Box) -> AppModel {
        let monitor = ProcessMonitor(psOutput: { box.ps }, startTime: { box.starts[$0] })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.ticksPerSecond = 1_000_000_000
        return model
    }

    func primaryLine(_ e: ManagerEnv) -> String { "501 1 1000 \(e.claude.executable.path)" }
    func workLine(_ e: ManagerEnv, _ work: Identity) -> String {
        "502 1 1000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)"
    }

    @Test func aWindowOpenBeforeTheUpdateRunsThePreviousClaude() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = workLine(e, work); box.starts = [502: 10_000_000_000]
        let m = model(e, box)
        var clock: UInt64 = 20_000_000_000
        m.abstimeNow = { clock }
        m.reload()
        #expect(m.staleAccounts.isEmpty)
        try FakeClaudeApp.make(in: e.home.url, version: "9.0.0")
        clock = 30_000_000_000
        m.reload()
        #expect(m.staleAccounts == [work.slug])
        #expect(AccountsView.staleLine(version: "9.0.0") == "Runs the previous Claude. Restart to use 9.0.0.")
    }

    @Test func claudeComingBackBareAfterAnUpdateIsSaid() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = workLine(e, work)
        let m = model(e, box)
        m.reload()
        try FakeClaudeApp.make(in: e.home.url, version: "9.0.0")
        box.ps = ""
        m.reload()
        #expect(m.message == nil)
        box.ps = primaryLine(e)
        m.reload()
        let said = try #require(m.message)
        #expect(said.title == "Claude restarted itself to update and came back as Personal, not Work.")
        #expect(said.detail == "Nothing was changed.")
        #expect(said.action == .reopenInstead(slug: work.slug))
        #expect(said.actionLabel == "Reopen Work")
        #expect(said.cancelLabel == "Keep Personal")
    }

    @Test func noBannerWithoutAVersionChange() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = workLine(e, work)
        let m = model(e, box)
        m.reload()
        box.ps = ""; m.reload()
        box.ps = primaryLine(e); m.reload()
        #expect(m.message == nil)
    }

    @Test func noBannerWhenThePersonOpensTheFirstAccount() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let personal = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = workLine(e, work)
        let m = model(e, box)
        m.reload()
        try FakeClaudeApp.make(in: e.home.url, version: "9.0.0")
        box.ps = ""; m.reload()
        m.markOpening(personal.slug)
        box.ps = primaryLine(e); m.reload()
        #expect(m.message == nil)
    }

    @Test func openingOnTheWrongFoldersIsSaidAfterTenSeconds() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        let m = model(e, box)
        var now = Date(timeIntervalSince1970: 1_000)
        m.now = { now }
        m.reload()
        m.requestedOpen(work.slug)
        box.ps = primaryLine(e)
        now += 5; m.reload()
        #expect(m.message == nil)
        now += 6; m.reload()
        #expect(m.message?.title == "Claude opened on Personal's folders, not Work's.")
        #expect(m.message?.detail == "Nothing was changed.")
    }

    // MARK: Restart, through the app's quit and launch (fakes here: nothing is signalled or opened)

    /// Pids above macOS's limit (99,999): even a path that signalled for real would reach no process.
    func farWorkLine(_ e: ManagerEnv, _ work: Identity) -> String {
        "4000002 1 1000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)"
    }

    final class Did: @unchecked Sendable { var steps: [String] = [] }

    func restartable(_ e: ManagerEnv, _ box: Box, _ did: Did) -> AppModel {
        let m = model(e, box)
        m.quitAccount = { did.steps.append("quit \($0.slug)"); box.ps = "" }
        m.launchAccount = { did.steps.append("open \($0)") }
        return m
    }

    @Test func restartQuitsWaitsThenOpensThroughTheAccountsApp() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box(), did = Did()
        box.ps = farWorkLine(e, work)
        let m = restartable(e, box, did)
        m.reload()
        await m.restart(work.slug)
        #expect(did.steps == ["quit work", "open work"])
    }

    @Test func twoRestartClicksOpenTheWindowOnce() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box(), did = Did()
        box.ps = farWorkLine(e, work)
        let m = restartable(e, box, did)
        m.reload()
        async let first: Void = m.restart(work.slug)
        async let second: Void = m.restart(work.slug)
        _ = await (first, second)
        #expect(did.steps.filter { $0.hasPrefix("open") } == ["open work"])
        #expect(m.restarting.isEmpty)
    }

    @Test func restartWhenIdleWaitsForClaudeCodeUnderTheWindowToEnd() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box(), did = Did()
        let window = farWorkLine(e, work)
        box.ps = window + "\n4000003 4000002 1000 \(work.desktopData(in: e.home.paths).path)/claude-code/2.1.280/claude"
        let m = restartable(e, box, did)
        m.idlePoll = .milliseconds(20)
        m.reload()
        m.restartWhenIdle(work.slug)
        try await Task.sleep(for: .milliseconds(150))
        #expect(did.steps.isEmpty)
        #expect(m.restartingWhenIdle == [work.slug])
        box.ps = window
        // Bounded: the waiting task ends after the launch, then leaves the set.
        for _ in 0..<250 where did.steps.count < 2 || !m.restartingWhenIdle.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(did.steps == ["quit work", "open work"])
        #expect(m.restartingWhenIdle.isEmpty)
    }

    @Test func reopenInsteadQuitsTheBareClaudeThenOpensTheAccount() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box(), did = Did()
        box.ps = "4000001 1 1000 \(e.claude.executable.path)"
        let m = restartable(e, box, did)
        m.reload()
        await m.reopenInstead(work.slug)
        #expect(did.steps == ["quit personal", "open work"])
    }

    @Test func theAlertHasOneButtonThatChangesNothingAndItSaysWhat() {
        let keep = UserMessage(title: "t", detail: "d", action: .reopenInstead(slug: "work"), actionLabel: "Reopen Work", cancelLabel: "Keep Personal")
        #expect(RootView.cancelTitle(for: keep) == "Keep Personal")
        #expect(RootView.cancelTitle(for: UserMessage(title: "t", detail: "d", action: .moveToApplications)) == "Not now")
        #expect(RootView.cancelTitle(for: UserMessage(title: "t", detail: "d")) == "OK")
    }

    @Test func aCardWaitingToRestartSaysWhen() {
        #expect(AccountsView.staleLine(version: "9.0.0", waiting: false) == "Runs the previous Claude. Restart to use 9.0.0.")
        #expect(AccountsView.staleLine(version: "9.0.0", waiting: true) == "Runs the previous Claude. Restarts when its Claude Code sessions end.")
    }
}
