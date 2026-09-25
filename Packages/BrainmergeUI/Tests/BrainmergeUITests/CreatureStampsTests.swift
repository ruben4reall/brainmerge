import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// What the creature reacts to: the model stamps only events it really detects.
@MainActor @Suite struct CreatureStampsTests {
    /// A clock the test moves by hand.
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 780_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }
    /// What `ps` says, changed by the test.
    final class Processes: @unchecked Sendable { var output = "" }

    func model(_ e: ManagerEnv, clock: Clock, processes: Processes = Processes()) -> AppModel {
        let monitor = ProcessMonitor(psOutput: { processes.output })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.now = { clock.now }
        return model
    }

    func save(_ e: ManagerEnv, _ name: String) throws {
        try Data("# \(name)\n".utf8).write(to: e.brain.root.appending(path: "\(name).md"))
        try BrainGit(brain: e.brain).commitAll(authorName: "Personal", authorEmail: "personal@brainmerge.local", message: "Brain update by Personal")
    }

    @Test func stampsKeepTheLastFourWithinASecond() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        // In the order they were stamped: a wake 1.5 s ago, then five errors from 0.4 s ago to now.
        let stamps = [CreatureMoment(.wake, date: now.addingTimeInterval(-1.5))] + (0..<5).reversed().map { CreatureMoment(.error, date: now.addingTimeInterval(-0.1 * Double($0))) }
        let kept = AppModel.pruned(stamps, now: now)
        #expect(kept.count == 4)
        #expect(kept.allSatisfy { $0.event == .error && now.timeIntervalSince($0.date) <= 1 })
        #expect(kept.first?.date == now.addingTimeInterval(-0.3) && kept.last?.date == now)
    }

    @Test func aSaveIsSeenOnlyAfterTheFirstRead() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "first")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        // The first read at launch is never a save, however recent its last commit.
        #expect(m.creatureStamps.isEmpty && m.memorySavedAt == nil)
        #expect(m.creatureState(at: clock.now) == .asleep)
        clock.advance(10)
        m.refreshMemory()
        #expect(m.creatureStamps.isEmpty)
        try save(e, "second")
        clock.advance(10)
        m.refreshMemory()
        #expect(m.creatureStamps == [CreatureMoment(.memorySaved, date: clock.now)])
        #expect(m.memorySavedAt == clock.now)
        // Read again with nothing new: nothing new.
        clock.advance(2)
        m.refreshMemory()
        #expect(m.creatureStamps.count == 1)
    }

    @Test func theGlowLastsExactlyFourSeconds() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "first")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        try save(e, "second")
        m.refreshMemory()
        let saved = try #require(m.memorySavedAt)
        #expect(m.creatureState(at: saved) == .glowing)
        #expect(m.creatureLine(at: saved) == "Memory saved just now")
        #expect(m.creatureState(at: saved.addingTimeInterval(3.99)) == .glowing)
        #expect(m.creatureState(at: saved.addingTimeInterval(4)) == .asleep)
        #expect(m.creatureLine(at: saved.addingTimeInterval(4)) == "No account open")
        #expect(m.glowEnds == saved.addingTimeInterval(4))
    }

    @Test func savesStampAtMostEveryOneAndAHalfSeconds() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "n0")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        var stampedAt = Set<Date>()
        for i in 1...4 {
            try save(e, "n\(i)")
            clock.advance(0.6)
            m.refreshMemory()
            // The glow always counts from the latest save.
            #expect(m.memorySavedAt == clock.now)
            stampedAt.formUnion(m.creatureStamps.filter { $0.event == .memorySaved }.map(\.date))
        }
        // Saves at 0.6, 1.2, 1.8 and 2.4 s: stamps at 0.6 and 2.4 (1.2 and 1.8 fall within 1.5 s of the one before).
        let start = Date(timeIntervalSinceReferenceDate: 780_000_000)
        #expect(stampedAt.map { $0.timeIntervalSince(start) }.map { ($0 * 10).rounded() / 10 }.sorted() == [0.6, 2.4])
    }

    @Test func switchingMemoriesIsNotASave() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "first")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let workBrain = Brain(root: work.url)
        try Data("# w\n".utf8).write(to: workBrain.root.appending(path: "w.md"))
        try BrainGit(brain: workBrain).commitAll(authorName: "Work", authorEmail: "work@brainmerge.local", message: "Brain update by Work")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        m.selectedBrainID = work.id
        m.selectedBrainID = try e.store.load().defaultBrain?.id
        #expect(m.creatureStamps.isEmpty && m.memorySavedAt == nil)
    }

    @Test func anOpenedAccountWavesButATimeoutDoesNot() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let clock = Clock(), processes = Processes()
        let m = model(e, clock: clock, processes: processes)
        await m.launch(minimum: .zero)
        // Opening, then its window runs: the wave.
        m.markOpening("work")
        #expect(m.creatureStamps.map(\.event) == [.wake])
        processes.output = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        clock.advance(2)
        m.reload()
        #expect(m.opening.isEmpty)
        #expect(m.creatureStamps.map(\.event) == [.accountOpened])   // the wake is more than a second old
        // An opening that times out is no wave (and the creature dozes only once nothing is open or opening).
        processes.output = ""
        clock.advance(2)
        m.reload()
        #expect(m.creatureStamps.map(\.event) == [.doze])
        clock.advance(2)
        m.markOpening("work", fallback: .milliseconds(20))
        // The fallback fires on the main actor: under load it can take a while, so wait for it (up to 10 s).
        for _ in 0..<500 where !m.opening.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.opening.isEmpty)
        #expect(!m.creatureStamps.contains { $0.event == .accountOpened })
    }

    @Test func theCreatureWakesAndDozesWithTheAccountsButNotAtLaunch() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let clock = Clock(), processes = Processes()
        processes.output = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        let m = model(e, clock: clock, processes: processes)
        // Launching with an account already open: the creature lands awake, no wake.
        await m.launch(minimum: .zero)
        #expect(m.creatureState(at: clock.now) == .awake && m.creatureStamps.isEmpty)
        #expect(m.creatureLine(at: clock.now) == "1 account open")
        processes.output = ""
        clock.advance(1)
        m.reload()
        #expect(m.creatureStamps.map(\.event) == [.doze])
        processes.output = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        clock.advance(0.5)
        m.reload()
        #expect(m.creatureStamps.map(\.event) == [.doze, .wake])
        // A reload that changes nothing stamps nothing.
        clock.advance(0.2)
        m.reload()
        #expect(m.creatureStamps.map(\.event) == [.doze, .wake])
    }

    @Test func theGlowEndingAsleepDozesOff() throws {
        // A save while no account is open: the hop opens the eyes and the glow keeps them open for 4 s. Then the creature
        // dozes off (heavy lids, then the asleep dash) instead of snapping to the dash, in the same redraw as its state.
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "first")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        try save(e, "second")
        m.refreshMemory()
        let saved = try #require(m.memorySavedAt), ends = saved.addingTimeInterval(4)
        #expect(m.creatureMoments(at: saved.addingTimeInterval(3.99)) == [CreatureMoment(.memorySaved, date: saved)])
        #expect(m.creatureState(at: ends.addingTimeInterval(0.001)) == .asleep)
        #expect(m.creatureMoments(at: ends.addingTimeInterval(0.001)).last == CreatureMoment(.doze, date: ends))
        // Once it has played, it goes, like any stamp.
        #expect(!m.creatureMoments(at: ends.addingTimeInterval(1.5)).contains { $0.event == .doze })
    }

    @Test func theGlowEndingAwakeKeepsTheEyesOpen() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try save(e, "first")
        let clock = Clock(), processes = Processes()
        processes.output = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        let m = model(e, clock: clock, processes: processes)
        await m.launch(minimum: .zero)
        try save(e, "second")
        m.refreshMemory()
        let ends = try #require(m.glowEnds)
        #expect(m.creatureState(at: ends.addingTimeInterval(0.001)) == .awake)
        #expect(m.creatureMoments(at: ends.addingTimeInterval(0.001)).map(\.event) == [.memorySaved])
    }

    @Test func accountsTurningDuringTheGlowStampNothing() async throws {
        // While it glows the creature shows its eyes whatever the accounts do: a doze or a wake would shut them over the
        // sparkles. The glow's end then dozes it if nothing is open any more.
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try save(e, "first")
        let clock = Clock(), processes = Processes()
        processes.output = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        let m = model(e, clock: clock, processes: processes)
        await m.launch(minimum: .zero)
        try save(e, "second")
        m.refreshMemory()
        let ends = try #require(m.glowEnds)
        clock.advance(1)
        processes.output = ""
        m.reload()
        #expect(m.creatureStamps.map(\.event) == [.memorySaved])
        clock.advance(1)
        m.markOpening("work", fallback: .milliseconds(20))
        #expect(m.creatureStamps.map(\.event) == [.memorySaved])
        // The opening times out (on the main actor: wait for it, up to 10 s), still inside the glow.
        for _ in 0..<500 where !m.opening.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.opening.isEmpty)
        #expect(m.creatureStamps.map(\.event) == [.memorySaved])
        #expect(m.creatureMoments(at: ends.addingTimeInterval(0.001)).last == CreatureMoment(.doze, date: ends))
        // After the glow, the accounts turn it again.
        clock.advance(3)
        m.markOpening("work", fallback: .milliseconds(20))
        #expect(m.creatureStamps.last?.event == .wake)
        for _ in 0..<500 where !m.opening.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func anErrorStartles() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let clock = Clock()
        let m = model(e, clock: clock)
        m.present(BrainmergeError.lockTimeout)
        #expect(m.message != nil)
        #expect(m.creatureStamps == [CreatureMoment(.error, date: clock.now)])
    }
}
