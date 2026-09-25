import CoreGraphics
import Foundation
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

    @Test func capturesNeverPlayTheHandOffs() {
        let clock = LaunchClock(finished: true, slow: 1, capture: true)
        clock.windowSize = size
        clock.leave(from: CGRect(x: 456, y: 117, width: 48, height: 33), reduceMotion: false, at: t0)
        #expect(clock.finished && !clock.leavingGuide)
    }
}
