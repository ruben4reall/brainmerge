import CoreGraphics
import Foundation
import Observation
import Testing
@testable import BrainmergeUI

/// The one clock the splash, the screens and the landing share: what it records, when it takes a target, when it ends.
@MainActor @Suite struct LaunchClockTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let size = CGSize(width: 960, height: 640)
    let sidebar = LaunchTarget(feet: CGPoint(x: 48, y: 612), unit: 2, asleep: false)
    func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }

    func started() -> LaunchClock {
        let clock = LaunchClock(slow: 1, capture: false)
        clock.begin(at: t0, reduceMotion: false)
        return clock
    }

    @Test func itRecordsReadyAndTheFirstSkipOnItsOwnTime() {
        let clock = started()
        clock.begin(at: at(5), reduceMotion: true)       // a second appearance never restarts it
        #expect(clock.start == t0 && !clock.reduceMotion)
        clock.skip(at: at(0.1))
        clock.skip(at: at(0.3))
        clock.ready(at: at(0.2))
        #expect(clock.skippedAt.map { abs($0 - 0.1) < 1e-6 } == true && clock.readyAt.map { abs($0 - 0.2) < 1e-6 } == true)
        #expect(clock.frame(at: at(0.2), size: size).handingOff)
    }

    @Test func itFreezesTheFirstTargetOfferedInTime() {
        let clock = started()
        clock.ready(at: at(0.2))
        let other = LaunchTarget(feet: CGPoint(x: 60, y: 600), unit: 2, asleep: true)
        clock.offer(sidebar, at: at(0.3))
        clock.offer(other, at: at(0.31))
        #expect(clock.target == sidebar)
        // Too late: once the leap has taken off (0.48 + 0.08), a target would bend the arc; the creature hops in place.
        let late = started()
        late.ready(at: at(0.2))
        late.offer(sidebar, at: at(0.57))
        #expect(late.target == nil)
    }

    @Test func itLandsOnTheExactFinishTimeAndHidesTheTargetUntilThen() {
        let clock = started()
        #expect(!clock.hidesTarget || clock.target == nil)
        clock.ready(at: at(0.2))
        clock.offer(sidebar, at: at(0.25))
        #expect(clock.hidesTarget && !clock.finished)
        #expect(clock.finishTime.map { abs($0 - 1.56) < 1e-9 } == true)
        clock.finish()
        #expect(clock.finished && !clock.hidesTarget)
        #expect(clock.landed.map { abs($0.timeIntervalSince(t0) - 1.56) < 1e-6 } == true)
        let reveal = clock.reveal(.main, at: at(0.5))
        #expect(reveal.opacity == 1 && reveal.scale == 1 && reveal.hittable)
    }

    @Test func slowMotionStretchesItsTime() {
        let clock = LaunchClock(slow: 4, capture: false)
        clock.begin(at: t0, reduceMotion: false)
        #expect(clock.time(at: at(2)) == 0.5)
        clock.ready(at: at(0.8))
        clock.offer(sidebar, at: at(0.9))
        clock.finish()
        #expect(clock.landed.map { abs($0.timeIntervalSince(t0) - 1.56 * 4) < 1e-6 } == true)
    }

    @Test func reduceMotionNeverHidesTheTarget() {
        let clock = LaunchClock(slow: 1, capture: false)
        clock.begin(at: t0, reduceMotion: true)
        clock.ready(at: at(0.2))
        clock.offer(sidebar, at: at(0.25))
        #expect(!clock.hidesTarget)
        #expect(clock.finishTime.map { abs($0 - 0.63) < 1e-9 } == true)
    }

    @Test func aWindowOpenedLaterHasNoSplash() {
        let clock = LaunchClock(finished: true, slow: 1, capture: false)
        #expect(clock.finished && !clock.showsBackdrop && !clock.hidesTarget && !clock.leavingGuide)
        clock.offer(sidebar, at: at(0))
        #expect(clock.target == nil)
        let reveal = clock.reveal(.guide, at: at(0))
        #expect(reveal.opacity == 1 && reveal.hittable)
    }

    @Test func theScreensFollowTheSameFrameAsTheSplash() {
        let clock = started()
        clock.ready(at: at(0.2))
        clock.offer(sidebar, at: at(0.25))
        #expect(clock.showsBackdrop)
        for t in stride(from: 0.4, through: 1.2, by: 0.05) {
            let frame = clock.frame(at: at(t), size: size)
            for role in [LaunchClock.Role.main, .guide] {
                let reveal = clock.reveal(role, at: at(t))
                #expect(reveal.opacity == frame.screensOpacity && reveal.scale == frame.screensScale && reveal.hittable)
            }
        }
    }

    @Test func leavingTheGuideLeapsFromAllSetToTheSidebar() {
        let clock = LaunchClock(finished: true, slow: 1, capture: false)
        clock.windowSize = size
        let allSet = CGRect(x: 456, y: 117, width: 48, height: 33)      // 16 by 11 cells of 3 pt
        clock.leave(from: allSet, reduceMotion: false, at: t0)
        #expect(!clock.finished && clock.leavingGuide && clock.hidesSource && !clock.showsBackdrop)
        #expect(clock.mode == .exit(source: LaunchTarget(frame: allSet, asleep: false)))
        clock.offer(sidebar, at: at(0.02))
        #expect(clock.target == sidebar && clock.hidesTarget)
        let guide = clock.reveal(.guide, at: at(0.1)), main = clock.reveal(.main, at: at(0.1))
        #expect(!guide.hittable && guide.opacity < 1 && main.hittable && main.opacity < 1)
        #expect(clock.frame(at: at(0), size: size).feet == CGPoint(x: 480, y: 150))
        #expect(clock.finishTime.map { abs($0 - 1.08) < 1e-9 } == true)
        clock.finish()
        #expect(clock.finished && !clock.leavingGuide && !clock.hidesSource && !clock.hidesTarget)
        #expect(clock.landed.map { abs($0.timeIntervalSince(t0) - 1.08) < 1e-6 } == true)
    }

    @Test func leavingWithTheCreatureOutOfSightOrReducedMotionDissolves() {
        for (rect, reduce) in [(CGRect(x: 456, y: -60, width: 48, height: 33), false), (nil, false),
                               (CGRect(x: 456, y: 117, width: 48, height: 33), true)] as [(CGRect?, Bool)] {
            let clock = LaunchClock(finished: true, slow: 1, capture: false)
            clock.windowSize = size
            clock.leave(from: rect, reduceMotion: reduce, at: t0)
            clock.offer(sidebar, at: at(0.01))
            #expect(clock.mode == .exit(source: nil) || reduce)
            #expect(!clock.hidesSource && !clock.hidesTarget && clock.leavingGuide)
        }
    }

    /// The words and rows on screen reach the leap, which finds its way around them; once the creature is in the air they
    /// hold (a new layout would bend its arc), and they follow the layout again once it has landed.
    @Test func itPassesTheWordsAndRowsToTheLeapAndHoldsThemInFlight() {
        let clock = started()
        clock.windowSize = size
        clock.ready(at: at(0.2))
        clock.offer(sidebar, at: at(0.25))
        let rows = CGRect(x: 20, y: 40, width: 206, height: 348), cards = CGRect(x: 264, y: 20, width: 666, height: 236)
        clock.offer(obstacle: "rows", frame: rows, at: at(0.3))
        clock.offer(obstacle: "cards", frame: cards, at: at(0.3))
        clock.offer(obstacle: "rows", frame: rows.insetBy(dx: 0, dy: 10), at: at(0.4))
        #expect(Set(clock.input(size: size).obstacles) == [rows.insetBy(dx: 0, dy: 10), cards])
        // In flight (0.48 + 0.08 on): held.
        clock.offer(obstacle: "cards", frame: nil, at: at(0.7))
        clock.offer(obstacle: "late", frame: rows, at: at(0.7))
        #expect(Set(clock.input(size: size).obstacles) == [rows.insetBy(dx: 0, dy: 10), cards])
        // Landed: the layout again (the guide's last leap measures the main window long after the launch).
        clock.finish()
        clock.offer(obstacle: "cards", frame: nil, at: at(3))
        #expect(clock.input(size: size).obstacles == [rows.insetBy(dx: 0, dy: 10)])
        // Only what is in the window counts, and nothing empty.
        clock.offer(obstacle: "below", frame: CGRect(x: 20, y: 700, width: 100, height: 40), at: at(3))
        clock.offer(obstacle: "empty", frame: .zero, at: at(3))
        #expect(clock.input(size: size).obstacles == [rows.insetBy(dx: 0, dy: 10)])
    }

    /// The All set creature's frame changes on every scroll step: kept outside observation, it never redraws the guide.
    @Test func theAllSetFrameIsKeptOutOfObservation() {
        let clock = LaunchClock(finished: true, slow: 1, capture: false)
        let changed = Flag()
        withObservationTracking { _ = clock.allSetFrame } onChange: { changed.raise() }
        clock.allSetFrame = CGRect(x: 333, y: 538, width: 48, height: 33)
        #expect(!changed.raised && clock.allSetFrame == CGRect(x: 333, y: 538, width: 48, height: 33))
    }
    final class Flag: @unchecked Sendable { var raised = false; func raise() { raised = true } }

    /// On a first run the welcome creature lands above the guide's first words: they come in once it has landed, one after
    /// the other, so its leap never crosses them. Reduce Motion, and every later window, shows them at once.
    @Test func theWelcomeWordsWaitForTheLanding() {
        let welcome = LaunchTarget(feet: CGPoint(x: 480, y: 188), unit: 4, asleep: false)
        let clock = started()
        clock.windowSize = size
        clock.ready(at: at(0.2))
        clock.offer(welcome, at: at(0.25))
        let touchdown = 0.48 + 0.08 + 0.50
        for i in 0..<4 { #expect(clock.words(i, at: at(touchdown - 0.001)).opacity == 0, "\(i)") }
        let first = clock.words(0, at: at(touchdown + 0.1)), second = clock.words(1, at: at(touchdown + 0.1))
        #expect(first.opacity > second.opacity && first.opacity > 0 && first.rise < 6 && first.rise > 0)
        for i in 0..<4 { #expect(clock.words(i, at: at(touchdown + 0.5)) == (1, 0), "\(i)") }
        #expect(clock.wordsRun)
        clock.finish()
        #expect(clock.words(0, at: at(touchdown)) == (1, 0) && !clock.wordsRun)
        let reduced = LaunchClock(slow: 1, capture: false)
        reduced.begin(at: t0, reduceMotion: true)
        reduced.ready(at: at(0.2))
        reduced.offer(welcome, at: at(0.25))
        #expect(reduced.words(0, at: at(0.5)) == (1, 0))
    }

    @Test func capturesNeverPlayTheHandOffs() {
        // A capture never shows the splash, even from a window that would.
        #expect(LaunchClock(finished: false, slow: 1, capture: true).finished)
        #expect(!LaunchClock(finished: false, slow: 1, capture: false).finished)
        let clock = LaunchClock(finished: true, slow: 1, capture: true)
        clock.windowSize = size
        clock.leave(from: CGRect(x: 456, y: 117, width: 48, height: 33), reduceMotion: false, at: t0)
        #expect(clock.finished && !clock.leavingGuide)
    }
}
