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
}
