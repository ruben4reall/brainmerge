import Foundation
import SwiftUI
import Testing
@testable import BrainmergeUI

/// The creature's timeline: 60 frames a second only while something moves smoothly, otherwise one date per stepped change,
/// and nothing when there is nothing to show.
@Suite struct CreatureScheduleTests {
    /// A real clock value: dates around 7.8e8 s lose precision, and the schedule must never stall on a boundary.
    static let start = Date(timeIntervalSinceReferenceDate: 780_000_000.123)

    static func schedule(_ mode: CreatureSchedule.Mode = .live, state: CreatureState = .awake, events: [CreatureStamp] = [],
                         profile: LifeProfile = .companion, walking: CreatureWalk? = nil, asleepSince: Double? = nil,
                         slow: Double = 1) -> CreatureSchedule {
        CreatureSchedule(start: start, mode: mode, state: state, events: events, profile: profile, walking: walking,
                         asleepSince: asleepSince, slow: slow)
    }
    /// The dates drawn, as scene times: the far-future date a finished timeline waits on is left out.
    static func times(_ s: CreatureSchedule, from t: Double = 0, count: Int, mode: TimelineScheduleMode = .normal) -> [Double] {
        Array(s.entries(from: start.addingTimeInterval(t), mode: mode).prefix(count)).filter { $0 != .distantFuture }.map { $0.timeIntervalSince(start) }
    }

    @Test func theIdleWakesOnlyForItsSteps() {
        let t = Self.times(Self.schedule(), count: 6)
        #expect(t.count == 6)
        #expect(abs(t[0]) < 1e-6)
        // The first blink's four steps: 1.3, 1.34, 1.40, 1.44 (a hair late, never early), then the first glance at 3.1.
        for (got, want) in zip(t.dropFirst(), [1.3, 1.34, 1.40, 1.44, 3.1]) { #expect(got >= want && got - want < 0.002, "\(got) for \(want)") }
    }

    @Test func eachEntryShowsTheChangeItWasFor() {
        // At every idle entry the frame differs from the one before: no wasted frame, and no step missed.
        let s = Self.schedule(profile: .stage)
        var previous: LifeFrame?
        for t in Self.times(s, count: 60) {
            let frame = CreatureLife.frame(state: .awake, t: t, profile: .stage)
            if let previous { #expect(frame != previous, "nothing changed at \(t)") }
            previous = frame
        }
    }

    @Test func aReactionGetsSixtyFramesASecondThenTheIdleResumes() {
        let s = Self.schedule(events: [CreatureStamp(.memorySaved, at: 2)])
        let t = Self.times(s, from: 1.9, count: 60)
        #expect(t[0] == 1.9 || abs(t[0] - 1.9) < 1e-6)
        #expect(abs(t[1] - 2) < 0.002)   // wakes up for the stamp
        let during = zip(t.dropFirst(), t.dropFirst(2)).map { $1 - $0 }.prefix(40)
        #expect(during.allSatisfy { abs($0 - 1.0 / 60) < 1e-4 })
        // After 0.74 s it goes back to stepped dates.
        #expect(t.last! > 2.74 && zip(t, t.dropFirst()).contains { $1 - $0 > 0.5 })
    }

    @Test func entriesAlwaysMoveForward() {
        for mode in [CreatureSchedule.Mode.live, .background, .reduced] {
            for profile in [LifeProfile.companion, .stage] {
                let s = Self.schedule(mode, events: [CreatureStamp(.error, at: 5), CreatureStamp(.memorySaved, at: 9)], profile: profile,
                                      walking: CreatureWalk(start: 12, end: 13))
                let t = Self.times(s, count: 400)
                #expect(zip(t, t.dropFirst()).allSatisfy { $1 - $0 >= 0.001 }, "\(mode)")
            }
        }
    }

    @Test func capturesAndLowFrequencyShowOneStill() {
        #expect(Self.times(Self.schedule(.still, events: [CreatureStamp(.memorySaved, at: 1)]), count: 10).count == 1)
        #expect(Self.times(Self.schedule(), count: 10, mode: .lowFrequency).count == 1)
    }

    @Test func reduceMotionOnlyFadesItsCues() {
        // Idle: nothing after the first frame.
        #expect(Self.times(Self.schedule(.reduced), count: 10).count == 1)
        // A save: its stars fade in and out (opacity only), then nothing.
        let t = Self.times(Self.schedule(.reduced, events: [CreatureStamp(.memorySaved, at: 1)]), count: 200)
        #expect(t.count < 200 && t.contains { $0 > 1 && $0 < 1.74 } && t.last! < 1.8)
        // An opened account, a wake, a doze: nothing moves at all.
        for e in [CreatureEvent.accountOpened, .wake, .doze] {
            #expect(Self.times(Self.schedule(.reduced, events: [CreatureStamp(e, at: 1)]), count: 10).count == 1)
        }
    }

    @Test func aBackgroundWindowPlaysReactionsButHoldsTheIdle() {
        #expect(Self.times(Self.schedule(.background), count: 10).count == 1)
        let t = Self.times(Self.schedule(.background, events: [CreatureStamp(.memorySaved, at: 1)]), count: 200)
        #expect(t.count < 200 && t.contains { $0 > 1 && $0 < 1.74 } && t.last! < 1.8)
        let walk = Self.times(Self.schedule(.background, walking: CreatureWalk(start: 0, end: 1)), count: 200)
        #expect(walk.count > 30 && walk.last! < 1.2)
    }

    /// SwiftUI never draws a schedule's last entry: a timeline that ends must reach the frame that stays, then wait on a
    /// far-future date, or the creature freezes on its last moving frame (eyes open while asleep, a sparkle hanging in the air,
    /// a fade at 5%, half a step).
    @Test func aTimelineThatEndsDrawsItsSettledFrameThenWaits() {
        let cases: [(String, CreatureSchedule, Double, LifeFrame)] = [
            ("asleep past a minute, then a save", Self.schedule(state: .asleep, events: [CreatureStamp(.memorySaved, at: 70.2)], asleepSince: 0),
             70, LifeFrame(pose: .asleep)),
            ("asleep past a minute, then an error", Self.schedule(state: .asleep, events: [CreatureStamp(.error, at: 70.2)], asleepSince: 0),
             70, LifeFrame(pose: .asleep)),
            ("background, a hop", Self.schedule(.background, events: [CreatureStamp(.memorySaved, at: 1)]), 0, LifeFrame(pose: .rest)),
            ("background, a walk and no wave", Self.schedule(.background, walking: CreatureWalk(start: 0.5, end: 1.1)), 0, LifeFrame(pose: .rest)),
            ("background asleep, an error", Self.schedule(.background, state: .asleep, events: [CreatureStamp(.error, at: 1)], asleepSince: 0),
             0, LifeFrame(pose: .asleep)),
            ("reduced, a save", Self.schedule(.reduced, events: [CreatureStamp(.memorySaved, at: 1)]), 0, LifeFrame()),
            ("reduced, an error", Self.schedule(.reduced, events: [CreatureStamp(.error, at: 1)]), 0, LifeFrame()),
            ("capture", Self.schedule(.still, state: .glowing), 0, CreatureLife.reducedFrame(state: .glowing, t: 0, events: [])),
        ]
        for (name, schedule, from, settled) in cases {
            let dates = Array(schedule.entries(from: Self.start.addingTimeInterval(from), mode: .normal).prefix(3000))
            #expect(dates.count < 3000 && dates.last == .distantFuture, "\(name) never waits")
            guard dates.count >= 2 else { continue }
            let drawnLast = schedule.frame(at: dates[dates.count - 2])
            #expect(drawnLast == settled, "\(name) ends on \(drawnLast)")
        }
        // Low frequency: the first date, then the wait.
        #expect(Array(Self.schedule().entries(from: Self.start, mode: .lowFrequency).prefix(10)) == [Self.start, .distantFuture])
    }

    @Test func theSleepLoopEndsTheTimeline() {
        let t = Self.times(Self.schedule(state: .asleep, asleepSince: 0), from: 55, count: 1000)
        #expect(t.count < 1000 && t.last! < 60)
    }

    @Test func slowMotionStretchesTheScene() {
        let t = Self.times(Self.schedule(slow: 4), count: 3)
        #expect(t[1] >= 4 * 1.3 && t[1] - 4 * 1.3 < 0.002)
        #expect(t[2] >= 4 * 1.34 && t[2] - 4 * 1.34 < 0.002)
    }

    @Test func eachModeDrawsItsOwnFrame() {
        let stamps = [CreatureStamp(.memorySaved, at: 1)]
        let at = { (t: Double) in Self.start.addingTimeInterval(t) }
        // Captures: the named still, whatever the time and the events.
        for state in [CreatureState.awake, .asleep, .glowing] {
            #expect(Self.schedule(.still, state: state, events: stamps).frame(at: at(1.3)) == CreatureLife.reducedFrame(state: state, t: 0, events: []))
            #expect(Self.schedule(.reduced, state: state, events: stamps).frame(at: at(1.3)) == CreatureLife.reducedFrame(state: state, t: 1.3, events: stamps))
        }
        // Live: the life itself (at the time the clock reads: a real date is not exact to 1e-13 s).
        let t = Self.schedule().time(at: at(1.3))
        #expect(abs(t - 1.3) < 1e-6)
        #expect(Self.schedule(.live, events: stamps).frame(at: at(1.3)) == CreatureLife.frame(state: .awake, t: t, events: stamps))
        #expect(Self.schedule(.live).frame(at: at(1.31)).pose.eyeHeight == 0.5)
        // In the background: the reaction plays, the idle holds still (no blink at 1.31, no Z).
        #expect(Self.schedule(.background, events: stamps).frame(at: at(1.3)) == CreatureLife.frame(state: .awake, t: t, events: stamps))
        #expect(Self.schedule(.background).frame(at: at(1.31)) == LifeFrame(pose: .rest))
        #expect(Self.schedule(.background, state: .asleep, asleepSince: 0).frame(at: at(2.5)) == LifeFrame(pose: .asleep))
    }

    @Test func theModeFollowsTheSettingsAndTheWindow() {
        #expect(CreatureSchedule.Mode(capture: true, reduceMotion: false, active: true) == .still)
        #expect(CreatureSchedule.Mode(capture: false, reduceMotion: true, active: true) == .reduced)
        #expect(CreatureSchedule.Mode(capture: false, reduceMotion: false, active: false) == .background)
        #expect(CreatureSchedule.Mode(capture: false, reduceMotion: false, active: true) == .live)
        #expect(CreatureSchedule.Mode(capture: true, reduceMotion: true, active: false) == .still)
    }

    @Test func theViewsClockReadsTheSameTime() {
        // The view turns a date into scene time the way the schedule does, and dated stamps into clock stamps.
        let s = Self.schedule(slow: 2)
        #expect(abs(s.time(at: Self.start.addingTimeInterval(3)) - 1.5) < 1e-6)
        let stamps = CreatureSchedule.stamps([CreatureMoment(.error, date: Self.start.addingTimeInterval(4))], since: Self.start, slow: 2)
        #expect(stamps.count == 1 && stamps[0].event == .error && abs(stamps[0].at - 2) < 1e-6)
    }
}
