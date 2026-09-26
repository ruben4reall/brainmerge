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
