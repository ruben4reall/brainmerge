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

    /// The window opening or closing changes the set of clocks: the clocks that keep running keep their phase (the
    /// minute and five-minute clocks are not started over), only the ones that stop or start are touched.
    @MainActor @Test func changingTheClocksKeepsTheOnesThatStillRun() {
        let log = ClockLog()
        let watchers = Watchers(schedule: { clock, tick in
            log.events.append("start \(clock)")
            log.ticks[clock] = tick
            return { log.events.append("stop \(clock)") }
        })
        func start(_ clocks: Set<Watchers.Clock>) {
            watchers.start(clocks, running: {}, memory: {}, projects: {}, claude: {})
        }
        start([.instances, .projects, .claude])
        #expect(log.events == ["start instances", "start projects", "start claude"])
        log.events = []
        start(Set(Watchers.Clock.allCases))   // the window opens
        #expect(log.events == ["start memory"])
        log.events = []
        start([.instances, .projects, .claude])   // the window closes
        #expect(log.events == ["stop memory"])
        log.events = []
        start([.instances, .projects, .claude])
        #expect(log.events.isEmpty)
        watchers.stop()
        #expect(Set(log.events) == ["stop instances", "stop projects", "stop claude"] && log.events.count == 3)
        log.events = []
        watchers.stop()
        #expect(log.events.isEmpty)
    }

    /// A clock that keeps running calls what the latest start asked for.
    @MainActor @Test func aKeptClockCallsTheLatestAction() throws {
        let log = ClockLog()
        let watchers = Watchers(schedule: { clock, tick in log.ticks[clock] = tick; return {} })
        let first = Tally(), second = Tally()
        watchers.start([.projects], running: {}, memory: {}, projects: { first.count += 1 }, claude: {})
        watchers.start([.projects, .memory], running: {}, memory: {}, projects: { second.count += 1 }, claude: {})
        let tick = try #require(log.ticks[.projects])
        tick()
        #expect(first.count == 0 && second.count == 1)
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

/// What a fake schedule was asked to do, and each clock's tick.
@MainActor final class ClockLog {
    var events: [String] = []
    var ticks: [Watchers.Clock: @MainActor () -> Void] = [:]
}
