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
}
