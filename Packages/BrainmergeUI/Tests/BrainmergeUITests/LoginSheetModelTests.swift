import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct LoginSheetModelTests {
    final class Box: @unchecked Sendable { var ps = "" }

    @Test func theAppClosesTheOthersThenOpensTheTargetAndReopensOnlyOnAClick() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = "501 1 1 \(e.claude.executable.path)"
        let monitor = ProcessMonitor(psOutput: { box.ps })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        var did: [String] = []
        m.quitAccount = { did.append("quit \($0.slug)") }
        m.launchAccount = { did.append("open \($0)") }
        m.reload()
        m.beginLogin(work.slug)
        #expect(m.login?.title == "Log in to Work")
        m.startLogin()
        #expect(did == ["quit personal"])
        m.reload()
        #expect(did == ["quit personal"])
        box.ps = ""
        m.reload()
        #expect(did == ["quit personal", "open work"])
        m.confirmLoggedIn()
        m.reload()
        #expect(did == ["quit personal", "open work"])
        m.reopenAfterLogin()
        #expect(did == ["quit personal", "open work", "open personal"])
        #expect(m.login == nil)
    }

    /// Personal's window at a pid above macOS's limit (99,999), Work to log in; quit and launch are fakes.
    func setUp(_ box: Box, _ did: Did) throws -> (ManagerEnv, AppModel, Identity) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        box.ps = "4000001 1 1 \(e.claude.executable.path)"
        let monitor = ProcessMonitor(psOutput: { box.ps })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.quitAccount = { did.steps.append("quit \($0.slug)") }
        m.launchAccount = { did.steps.append("open \($0)") }
        return (e, m, work)
    }

    final class Did: @unchecked Sendable { var steps: [String] = [] }

    @Test func cancelWhileAWindowIsClosingReopensItOnceItHasClosed() throws {
        let box = Box(), did = Did()
        let (e, m, work) = try setUp(box, did); defer { e.home.remove() }
        m.reload()
        m.beginLogin(work.slug)
        m.startLogin()
        m.cancelLogin()
        #expect(m.login == nil)
        #expect(did.steps == ["quit personal"])
        m.reload()
        #expect(did.steps == ["quit personal"])
        box.ps = ""
        m.reload()
        #expect(did.steps == ["quit personal", "open personal"])
        m.reload()
        #expect(did.steps == ["quit personal", "open personal"])
    }

    @Test func aWindowThatNeverClosesIsNotReopenedLater() throws {
        let box = Box(), did = Did()
        let (e, m, work) = try setUp(box, did); defer { e.home.remove() }
        var now = Date(timeIntervalSince1970: 1_000)
        m.now = { now }
        m.reload()
        m.beginLogin(work.slug)
        m.startLogin()
        m.cancelLogin()
        now += 31
        m.reload()
        // Quit by hand much later: it stays closed.
        box.ps = ""
        m.reload()
        #expect(did.steps == ["quit personal"])
    }
}
