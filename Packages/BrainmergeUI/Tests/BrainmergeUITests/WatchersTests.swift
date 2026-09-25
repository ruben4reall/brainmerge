import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@Suite struct WatchersTests {
    @Test func rebuildOnlyTintedClonesThatAreStoppedAndStale() {
        let clone = Identity(slug: "a", name: "A", iconMode: .tintedClone, builtForClaudeVersion: "2.7032.0")
        let launcher = Identity(slug: "b", name: "B", iconMode: .launcher, builtForClaudeVersion: "2.7032.0")
        #expect(UpdatePolicy.shouldRebuild(identity: clone, installedVersion: "2.8000.0", running: false, autoRebuild: true))
        #expect(!UpdatePolicy.shouldRebuild(identity: clone, installedVersion: "2.7032.0", running: false, autoRebuild: true))
        #expect(!UpdatePolicy.shouldRebuild(identity: clone, installedVersion: "2.8000.0", running: true, autoRebuild: true))
        #expect(!UpdatePolicy.shouldRebuild(identity: clone, installedVersion: "2.8000.0", running: false, autoRebuild: false))
        #expect(!UpdatePolicy.shouldRebuild(identity: launcher, installedVersion: "2.8000.0", running: false, autoRebuild: true))
        // The primary's own app opens Claude itself: nothing to follow after a Claude update, whatever the state says.
        let primary = Identity(slug: "ruben", name: "Ruben", isPrimary: true, iconMode: .tintedClone, builtForClaudeVersion: "2.7032.0", ownApp: true)
        #expect(!UpdatePolicy.shouldRebuild(identity: primary, installedVersion: "2.8000.0", running: false, autoRebuild: true))
    }

    /// With the window open, every clock runs. With only the icon, the ones that keep the menu's words true and the copies
    /// current; the memory's history only matters on screen. Nothing during the guided setup, nothing with neither.
    @Test func planByWindowAndIcon() {
        let all = Set(Watchers.Clock.allCases)
        for icon in [true, false] {
            #expect(Watchers.plan(windowOpen: true, iconShown: icon, needsOnboarding: false) == all)
            #expect(Watchers.plan(windowOpen: true, iconShown: icon, needsOnboarding: true).isEmpty)
            #expect(Watchers.plan(windowOpen: false, iconShown: icon, needsOnboarding: true).isEmpty)
        }
        #expect(Watchers.plan(windowOpen: false, iconShown: true, needsOnboarding: false) == [.instances, .projects, .claude])
        #expect(Watchers.plan(windowOpen: false, iconShown: false, needsOnboarding: false).isEmpty)
        #expect(Watchers.Clock.allCases.map(\.interval) == [3, 10, 60, 300])
    }

    @MainActor @Test func oneProcessListPerRefreshTick() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        for name in ["A", "B", "C", "D", "E"] { _ = try e.manager.add(IdentityManager.AddRequest(name: name)) }
        let counter = PSCounter()
        let monitor = ProcessMonitor(psOutput: { counter.bump(); return "" })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.reload()
        #expect(model.accounts.count == 6)
        #expect(counter.value == 1)
    }
}

final class PSCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
