import Foundation
import Testing
@testable import BrainmergeUI

@Suite struct UpdateWatchTests {
    // One tick per nanosecond, as on Intel; the rule does not depend on the ratio.
    let tps = 1_000_000_000.0
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Claude was replaced 30 s before the change was seen, at abstime 100 s.
    func change(seenAfter seconds: TimeInterval = 30) -> UpdateWatch.Change {
        UpdateWatch.Change(version: "1.2.4", observedAbstime: 100_000_000_000, observedAt: t0.addingTimeInterval(seconds), bundleModified: t0)
    }

    @Test func aWindowStartedBeforeTheUpdateIsStale() {
        // Started at 60 s: before the replacement, which happened at 70 s in abstime.
        #expect(UpdateWatch.isStale(startAbstime: 60_000_000_000, change: change(), ticksPerSecond: tps))
    }

    @Test func aWindowStartedAfterTheUpdateIsFresh() {
        #expect(!UpdateWatch.isStale(startAbstime: 75_000_000_000, change: change(), ticksPerSecond: tps))
        #expect(!UpdateWatch.isStale(startAbstime: nil, change: change(), ticksPerSecond: tps))
        #expect(!UpdateWatch.isStale(startAbstime: 1, change: nil, ticksPerSecond: tps))
    }

    @Test func aMacThatSleptOnlyMakesFewerWindowsStale() {
        // An hour of sleep between the replacement and the check: wall time ran on, abstime did not. The cut moves
        // back by the wall time, so a window started at 60 s (really before) is no longer called stale: never more.
        let slept = change(seenAfter: 3_600 + 30)
        #expect(UpdateWatch.cutoff(of: slept, ticksPerSecond: tps) == 0)
        #expect(!UpdateWatch.isStale(startAbstime: 60_000_000_000, change: slept, ticksPerSecond: tps))
    }

    // MARK: The bare relaunch

    func bare(exitAgo: TimeInterval? = 20, primaryWasRunning: Bool = false, versionChanged: Bool = true, openedByPerson: Bool = false) -> Bool {
        UpdateWatch.isBareRelaunch(now: t0, lastSecondaryExit: exitAgo.map { t0.addingTimeInterval(-$0) },
                                   primaryWasRunning: primaryWasRunning, versionChanged: versionChanged, primaryOpenedByPerson: openedByPerson)
    }

    @Test func aBareClaudeAfterAnUpdateNeedsAllFourConditions() {
        #expect(bare())
        #expect(!bare(exitAgo: nil))
        #expect(!bare(exitAgo: 61))
        #expect(!bare(primaryWasRunning: true))
        #expect(!bare(versionChanged: false))
    }

    @Test func openingTheFirstAccountDeliberatelyStaysSilent() {
        #expect(!bare(openedByPerson: true))
    }

    @Test func openingOnTheWrongFoldersIsSaidOnlyAfterTenSeconds() {
        let since = t0
        #expect(!UpdateWatch.openedElsewhere(since: since, now: since.addingTimeInterval(9), targetRunning: false, bareAppeared: true))
        #expect(UpdateWatch.openedElsewhere(since: since, now: since.addingTimeInterval(10), targetRunning: false, bareAppeared: true))
        #expect(!UpdateWatch.openedElsewhere(since: since, now: since.addingTimeInterval(11), targetRunning: true, bareAppeared: true))
        #expect(!UpdateWatch.openedElsewhere(since: since, now: since.addingTimeInterval(11), targetRunning: false, bareAppeared: false))
    }

    // MARK: The tracker, fed one snapshot at a time

    typealias W = UpdateWatch.Window
    func personal(_ running: Bool, start: UInt64? = nil) -> W { W(slug: "personal", isPrimary: true, running: running, startAbstime: start) }
    func work(_ running: Bool, start: UInt64? = nil) -> W { W(slug: "work", isPrimary: false, running: running, startAbstime: start) }

    /// One reload: `seconds` after t0 on the wall clock, the same in mach time (one tick per nanosecond).
    func see(_ watch: inout UpdateWatch, _ version: String, _ windows: [W], at seconds: TimeInterval, modified: TimeInterval? = nil) -> [UpdateWatch.Event] {
        watch.observe(version: version, windows: windows, now: t0.addingTimeInterval(seconds),
                      abstime: UInt64(seconds * 1_000_000_000), ticksPerSecond: tps,
                      bundleModified: { modified.map { self.t0.addingTimeInterval($0) } })
    }

    @Test func theTrackerFlagsOnlyWindowsStartedBeforeTheChange() {
        var watch = UpdateWatch()
        _ = see(&watch, "1.2.3", [work(true, start: 10_000_000_000), personal(true, start: 28_000_000_000)], at: 20)
        #expect(watch.stale.isEmpty)
        // Seen at 30 s, the bundle changed at 25 s: the cut is at 25 s in mach time.
        _ = see(&watch, "1.2.4", [work(true, start: 10_000_000_000), personal(true, start: 28_000_000_000)], at: 30, modified: 25)
        #expect(watch.change?.version == "1.2.4")
        #expect(watch.stale == ["work"])
        // Restarted after the update: fresh.
        _ = see(&watch, "1.2.4", [work(true, start: 40_000_000_000), personal(true, start: 28_000_000_000)], at: 45)
        #expect(watch.stale.isEmpty)
    }

    @Test func theTrackerSaysABareRelaunchOnlyWithAllFourConditions() {
        // Every reload's events: one said too early counts as much as one said at the end.
        func run(exitAt: TimeInterval = 40, bareAt: TimeInterval = 60, newVersion: String = "1.2.4", primaryBefore: Bool = false,
                 opened: Bool = false) -> [UpdateWatch.Event] {
            var watch = UpdateWatch()
            var events = see(&watch, "1.2.3", [personal(primaryBefore), work(true)], at: 10)
            events += see(&watch, newVersion, [personal(primaryBefore), work(false)], at: exitAt, modified: exitAt - 1)
            if opened { watch.requestedOpen("personal", at: t0.addingTimeInterval(bareAt - 2)) }
            events += see(&watch, newVersion, [personal(true), work(false)], at: bareAt)
            return events
        }
        #expect(run() == [.bareRelaunch(instead: "work")])
        #expect(run(bareAt: 101) == [])
        #expect(run(newVersion: "1.2.3") == [])
        #expect(run(primaryBefore: true) == [])
        #expect(run(opened: true) == [])
    }

    @Test func aRelaunchCaughtWithinOneReloadIsStillSaid() {
        var watch = UpdateWatch()
        _ = see(&watch, "1.2.3", [personal(false), work(true)], at: 10)
        #expect(see(&watch, "1.2.4", [personal(true), work(false)], at: 13, modified: 12) == [.bareRelaunch(instead: "work")])
    }

    @Test func theFirstAccountOpenWhenTheOtherClosedIsNeverABareRelaunch() {
        // Work is quit while Personal is open; Personal then restarts itself to update and is gone for one reload.
        var watch = UpdateWatch()
        var events = see(&watch, "1.2.3", [personal(true), work(true)], at: 10)
        events += see(&watch, "1.2.3", [personal(true), work(false)], at: 20)
        events += see(&watch, "1.2.4", [personal(false), work(false)], at: 30, modified: 29)
        events += see(&watch, "1.2.4", [personal(true), work(false)], at: 33)
        #expect(events == [])
    }

    @Test func aDeliberateOpenStaysSilentOnLaterReloadsToo() {
        var watch = UpdateWatch()
        var events = see(&watch, "1.2.3", [personal(false), work(true)], at: 10)
        events += see(&watch, "1.2.4", [personal(false), work(false)], at: 40, modified: 39)
        watch.requestedOpen("personal", at: t0.addingTimeInterval(44))
        events += see(&watch, "1.2.4", [personal(true), work(false)], at: 45)
        events += see(&watch, "1.2.4", [personal(true), work(false)], at: 48)
        #expect(events == [])
    }

    @Test func anOldUpdateDoesNotMakeALaterRelaunchBare() {
        var watch = UpdateWatch()
        _ = see(&watch, "1.2.3", [personal(false), work(true)], at: 10)
        _ = see(&watch, "1.2.4", [personal(false), work(true)], at: 20, modified: 19)
        _ = see(&watch, "1.2.4", [personal(false), work(false)], at: 900)
        #expect(see(&watch, "1.2.4", [personal(true), work(false)], at: 910) == [])
    }

    @Test func theTrackerSaysAnOpenOnTheWrongFoldersAfterTenSeconds() {
        var watch = UpdateWatch()
        _ = see(&watch, "1.2.3", [personal(false), work(false)], at: 0)
        watch.requestedOpen("work", at: t0.addingTimeInterval(1))
        #expect(see(&watch, "1.2.3", [personal(true), work(false)], at: 5) == [])
        #expect(see(&watch, "1.2.3", [personal(true), work(false)], at: 11) == [.openedElsewhere(target: "work")])
        // Said once.
        #expect(see(&watch, "1.2.3", [personal(true), work(false)], at: 14) == [])
    }

    @Test func anAccountThatOpensIsNeverSaidToHaveOpenedElsewhere() {
        var watch = UpdateWatch()
        _ = see(&watch, "1.2.3", [personal(false), work(false)], at: 0)
        watch.requestedOpen("work", at: t0)
        _ = see(&watch, "1.2.3", [personal(true), work(true)], at: 5)
        #expect(see(&watch, "1.2.3", [personal(true), work(true)], at: 12) == [])
    }

    // MARK: Restart

    final class Log: @unchecked Sendable { var steps: [String] = []; var running = true; var polls = 0 }

    @Test func restartWaitsForTheExitThenLaunchesOnce() async {
        let log = Log()
        let done = await UpdateWatch.restart(
            quit: { log.steps.append("quit") },
            isRunning: { log.polls += 1; if log.polls >= 3 { log.running = false }; return log.running },
            launch: { log.steps.append("launch") },
            pause: { _ in })
        #expect(done)
        #expect(log.steps == ["quit", "launch"])
    }

    @Test func restartNeverLaunchesWhenTheWindowDoesNotExit() async {
        let log = Log()
        let done = await UpdateWatch.restart(quit: { log.steps.append("quit") }, isRunning: { true },
                                             launch: { log.steps.append("launch") }, pause: { _ in })
        #expect(!done)
        #expect(log.steps == ["quit"])
    }
}
