import CoreGraphics
import Foundation
import Testing
@testable import BrainmergeUI

/// The creature's life: a pure function of the state, the view's clock and the stamped events.
@Suite struct CreatureLifeTests {
    static let events: [CreatureEvent] = [.wake, .doze, .memorySaved, .accountOpened, .error]
    static let profiles: [(String, LifeProfile)] = [("companion", .companion), ("stage", .stage)]

    static func pose(_ state: CreatureState = .awake, _ t: Double, _ events: [CreatureStamp] = [], profile: LifeProfile = .companion,
                     walking: CreatureWalk? = nil, asleepSince: Double? = nil) -> Creature.Pose {
        CreatureLife.frame(state: state, t: t, events: events, profile: profile, walking: walking, asleepSince: asleepSince, reduceMotion: false).pose
    }
    /// The body only: where it is, its size and its limbs (eyes blink on their own clock).
    static func bodyAtRest(_ p: Creature.Pose, tolerance: CGFloat = 0.02) -> Bool {
        abs(p.offset.dx) < tolerance && abs(p.offset.dy) < tolerance && abs(p.scaleX - 1) < tolerance && abs(p.scaleY - 1) < tolerance
            && p.armLeft == .rest && p.armRight == .rest && !p.legsTucked && p.raise == 0 && p.liftedLegs.allSatisfy { !$0 }
    }

    @Test func restIsTheGrid() {
        let f = CreatureLife.frame(state: .awake, t: 0, events: [], profile: .companion, reduceMotion: false)
        #expect(f.pose == .rest)
        #expect(f.sprites.isEmpty)
        #expect(Creature.cells(for: f.pose) == Creature.cells(for: .rest))
        #expect(CreatureLife.frame(state: .asleep, t: 0, events: [], profile: .companion, reduceMotion: false).pose == .asleep)
    }

    @Test func everyReactionStartsAndEndsAtRest() {
        #expect(CreatureEvent.wake.duration == 0.46 && CreatureEvent.doze.duration == 0.70 && CreatureEvent.memorySaved.duration == 0.74)
        #expect(CreatureEvent.accountOpened.duration == 0.62 && CreatureEvent.error.duration == 0.72)
        for (name, profile) in Self.profiles {
            for e in Self.events {
                #expect(e.duration < 0.8)
                let state: CreatureState = e == .doze ? .asleep : .awake
                let stamps = [CreatureStamp(e, at: 1)]
                let start = Self.pose(state, 1, stamps, profile: profile), end = Self.pose(state, 1 + e.duration - 1e-4, stamps, profile: profile)
                // Smooth fields start where the idle left them; stepped ones (the wave's first arm frame) may step at once.
                #expect(abs(start.offset.dy) < 0.02 && abs(start.scaleX - 1) < 0.02 && abs(start.scaleY - 1) < 0.02, "\(e) \(name) jumps in")
                #expect(Self.bodyAtRest(end), "\(e) \(name) ends away from rest: \(end)")
                #expect(end.breath == 0 || e != .doze, "\(e) \(name)")
                // Once over, the idle takes the body back exactly.
                #expect(Self.bodyAtRest(Self.pose(state, 1 + e.duration, stamps, profile: profile), tolerance: 1e-9), "\(e) \(name)")
            }
        }
    }

    @Test func deterministic() {
        for (_, profile) in Self.profiles {
            for state in [CreatureState.awake, .asleep, .glowing] {
                for t in stride(from: 0.0, to: 120, by: 0.37) {
                    let stamps = [CreatureStamp(.memorySaved, at: 30), CreatureStamp(.error, at: 60.1)]
                    let a = CreatureLife.frame(state: state, t: t, events: stamps, profile: profile, reduceMotion: false)
                    let b = CreatureLife.frame(state: state, t: t, events: stamps, profile: profile, reduceMotion: false)
                    #expect(a == b)
                }
            }
        }
        // Another seed, another rhythm.
        let a = (0..<600).map { Self.pose(.awake, Double($0) / 10) }
        let b = (0..<600).map { CreatureLife.frame(state: .awake, t: Double($0) / 10, events: [], profile: .companion, seed: 11, reduceMotion: false).pose }
        #expect(a != b)
    }

    @Test func idleIsMostlyStill() {
        // The companion is exactly the grid more than 85% of the time: subtle enough for a sidebar seen all day.
        var still = 0, n = 0
        for t in stride(from: 0.0, to: 120, by: 1.0 / 30) {
            if Self.pose(.awake, t) == .rest { still += 1 }
            n += 1
        }
        #expect(Double(still) / Double(n) > 0.85)
        // And it does live: blinks and glances both happen.
        let poses = stride(from: 0.0, to: 120, by: 1.0 / 60).map { Self.pose(.awake, $0) }
        #expect(poses.contains { $0.eyeHeight < 1 } && poses.contains { $0.look != 0 })
    }

    @Test func theFirstBlinkAndGlanceGreet() {
        // The companion's first blink 1.3 s after its clock starts, its first glance at 3.1 s.
        #expect(Self.pose(.awake, 1.29).eyeHeight == 1)
        #expect(Self.pose(.awake, 1.31).eyeHeight == 0.5)
        #expect(Self.pose(.awake, 1.36).eyeHeight == 0.2)
        #expect(Self.pose(.awake, 1.42).eyeHeight == 0.5)
        #expect(Self.pose(.awake, 1.45).eyeHeight == 1)
        #expect(Self.pose(.awake, 3.09).look == 0)
        #expect(Self.pose(.awake, 3.2).look != 0)
    }

    @Test func blinksKeepApart() {
        // No blink starts within 1 s of another, except a double blink's partner, 0.24 s after it.
        for (name, profile) in Self.profiles {
            var starts: [Double] = []
            var last: CGFloat = 1
            for i in 0..<(400 * 500) {
                let t = Double(i) / 500
                let h = Self.pose(.awake, t, profile: profile).eyeHeight
                if last == 1, h < 1 { starts.append(t) }
                last = h
            }
            #expect(starts.count > 40, "\(name) blinks \(starts.count) times")
            var previous = -Double.infinity, doubles = 0
            for s in starts {
                let gap = s - previous
                if abs(gap - 0.24) < 0.003 { doubles += 1 } else { #expect(gap >= 1 - 0.003, "\(name): blinks \(gap) s apart at \(s)") }
                previous = s
            }
            #expect(doubles > 0, "\(name) never blinks twice")
        }
    }

    @Test func glancesMoveOneWholeCell() {
        for (_, profile) in Self.profiles {
            for i in 0..<(200 * 60) {
                let p = Self.pose(.awake, Double(i) / 60, profile: profile)
                #expect((-1...1).contains(p.look))
                #expect([1, 0.5, 0.2].contains(p.eyeHeight))
            }
        }
    }

    @Test func breathStaysInWholeDevicePixels() {
        for (name, profile) in Self.profiles {
            for (state, amp) in [(CreatureState.awake, profile.awakeBreath), (.asleep, profile.sleepBreath)] {
                var last = 0, seen = Set<Int>()
                for i in 0..<(30 * 240) {
                    let b = Self.pose(state, Double(i) / 240, profile: profile, asleepSince: 0).breath
                    #expect((0...amp).contains(b), "\(name) \(state)")
                    #expect(abs(b - last) <= 1, "\(name) \(state) jumps")
                    last = b; seen.insert(b)
                }
                #expect(seen == Set(0...amp), "\(name) \(state) breathes \(seen)")
            }
        }
        // The companion never breathes while awake: in the sidebar, only the eyes live.
        #expect(LifeProfile.companion.awakeBreath == 0 && LifeProfile.companion.sleepBreath == 1)
        #expect(LifeProfile.stage.awakeBreath == 2 && LifeProfile.stage.sleepBreath == 2)
    }

    @Test func theProfilesAreTheSpecsTable() {
        // MOTION.md 2.1: how often each place blinks and glances (seconds), breathes (device pixels) and how high it hops (cells).
        #expect(LifeProfile.companion == LifeProfile(blinkEvery: 3.4...7.5, glanceEvery: 9...16, awakeBreath: 0, sleepBreath: 1, hopHeight: 1.75))
        #expect(LifeProfile.stage == LifeProfile(blinkEvery: 2.6...6.0, glanceEvery: 5.5...10, awakeBreath: 2, sleepBreath: 2, hopHeight: 2.25))
    }

    @Test func reduceMotionNeverMoves() {
        let stamps = [CreatureStamp(.memorySaved, at: 0.2), CreatureStamp(.error, at: 1), CreatureStamp(.accountOpened, at: 1.5),
                      CreatureStamp(.wake, at: 2.2), CreatureStamp(.doze, at: 3)]
        for t in stride(from: 0.0, to: 4, by: 0.01) {
            for state in [CreatureState.awake, .glowing] {
                let f = CreatureLife.frame(state: state, t: t, events: stamps, profile: .stage, walking: CreatureWalk(start: 0),
                                           reduceMotion: true)
                #expect(f.pose == .rest)
                #expect(f == CreatureLife.reducedFrame(state: state, t: t, events: stamps))
            }
            #expect(CreatureLife.frame(state: .asleep, t: t, events: stamps, profile: .stage, reduceMotion: true).pose == .asleep)
        }
    }

    @Test func reduceMotionShowsStillCues() {
        // Asleep: the dash and one still Z at 50%. Glowing: three still crosses at 70%.
        let asleep = CreatureLife.reducedFrame(state: .asleep, t: 5, events: [])
        #expect(asleep.sprites.count == 1 && asleep.sprites[0].opacity == 0.5)
        let glowing = CreatureLife.reducedFrame(state: .glowing, t: 5, events: [])
        #expect(glowing.sprites.count == 3 && glowing.sprites.allSatisfy { $0.opacity == 0.7 && $0.pattern.count == 3 })
        #expect(glowing.sprites.map(\.color) == [Theme.Colors.accentLight, Theme.Colors.text, Theme.Colors.accentLight])
        // A save: three cream stars fade in over 0.15 s, hold, fade out over 0.15 s. An error: the "!" the same way.
        let save = [CreatureStamp(.memorySaved, at: 1)]
        #expect(CreatureLife.reducedFrame(state: .awake, t: 0.99, events: save).sprites.isEmpty)
        let early = CreatureLife.reducedFrame(state: .awake, t: 1.075, events: save).sprites
        #expect(early.count == 3 && early.allSatisfy { abs($0.opacity - 0.5) < 1e-6 && $0.color == Theme.Colors.text })
        #expect(CreatureLife.reducedFrame(state: .awake, t: 1.4, events: save).sprites.allSatisfy { $0.opacity == 1 })
        #expect(CreatureLife.reducedFrame(state: .awake, t: 1.75, events: save).sprites.isEmpty)
        let error = CreatureLife.reducedFrame(state: .awake, t: 1.4, events: [CreatureStamp(.error, at: 1)]).sprites
        #expect(error.count == 1 && error[0].pattern.count == 6)
        // Wake, doze and an opened account change nothing but the eyes.
        for e in [CreatureEvent.wake, .doze, .accountOpened] {
            #expect(CreatureLife.reducedFrame(state: .awake, t: 1.2, events: [CreatureStamp(e, at: 1)]) == CreatureLife.reducedFrame(state: .awake, t: 1.2, events: []))
        }
    }

    @Test func interruptionHasNoJump() {
        // An error 0.25 s into a hop: the body blends from mid-air instead of snapping to the ground.
        for (_, profile) in Self.profiles {
            let stamps = [CreatureStamp(.memorySaved, at: 1), CreatureStamp(.error, at: 1.25)]
            var previous = Self.pose(.awake, 1.25 - 1.0 / 120, stamps, profile: profile)
            for i in 0...60 {
                let p = Self.pose(.awake, 1.25 + Double(i) / 120, stamps, profile: profile)
                #expect(abs(p.offset.dy - previous.offset.dy) < 0.4, "frame \(i)")
                #expect(abs(p.scaleY - previous.scaleY) < 0.1, "frame \(i)")
                previous = p
            }
        }
    }

    @Test func waveNeverUsesOut() {
        let stamps = [CreatureStamp(.accountOpened, at: 1)]
        var arms: [ArmPose] = []
        for i in 0...700 {
            let p = Self.pose(.awake, 1 + Double(i) / 1000, stamps)
            #expect(p.armRight != .out && p.armLeft == .rest)
            if arms.last != p.armRight { arms.append(p.armRight) }
        }
        #expect(arms == [.lift1, .up, .lift1, .up, .lift1, .up, .lift1, .rest])
        // The startle keeps `out`, on both arms: hands thrown up.
        let startle = Self.pose(.awake, 1.1, [CreatureStamp(.error, at: 1)])
        #expect(startle.armLeft == .out && startle.armRight == .out)
    }

    @Test func theStartleWidensTheEyesThenBlinks() {
        // Eyes 1.35 high (growing upward from their bottom row) until 0.40 s, open, then a relieved blink at 0.56 s.
        let error = [CreatureStamp(.error, at: 1)]
        for tau in [0.0, 0.1, 0.3, 0.39] {
            let p = Self.pose(.awake, 1 + tau, error)
            #expect(p.eyeHeight == 1.35 && p.eyeBottom == 2, "\(tau)")
        }
        #expect(Self.pose(.awake, 1.45, error).eyeHeight == 1)
        #expect(Self.pose(.awake, 1.58, error).eyeHeight == 0.5)
        #expect(Self.pose(.awake, 1.62, error).eyeHeight == 0.2)
    }

    @Test func theHopLeavesTheGroundWithItsArmsUpAndSparkles() {
        // The sidebar hops 1.75 cells (3.5 pt), a stage 2.25 cells.
        for (name, profile, height) in [("companion", LifeProfile.companion, 1.75), ("stage", .stage, 2.25)] {
            let stamps = [CreatureStamp(.memorySaved, at: 1)]
            let apex = Self.pose(.awake, 1.30, stamps, profile: profile)
            #expect(abs(apex.offset.dy + height) < 1e-6, "\(name)")
            #expect(apex.legsTucked && apex.armLeft == .up && apex.armRight == .up)
            let crouch = Self.pose(.awake, 1.07, stamps, profile: profile)
            #expect(crouch.scaleY < 0.9 && crouch.scaleX > 1.05 && crouch.eyeHeight == 0.5)
            let sparkles = CreatureLife.frame(state: .awake, t: 1.37, events: stamps, profile: profile, reduceMotion: false).sprites
            #expect(sparkles.count == 4, "\(name)")
            // Sparkles stay in the world while the body falls away from them: none follows the body.
            let later = CreatureLife.frame(state: .awake, t: 1.5, events: stamps, profile: profile, reduceMotion: false).sprites
            #expect(later.allSatisfy { $0.center.y < -profile.hopHeight + 0.5 })
        }
    }

    @Test func glowingTwinklesOneAtATimeButNotDuringTheHop() {
        let stamps = [CreatureStamp(.memorySaved, at: 1)]
        for i in 0..<(6 * 120) {
            let t = Double(i) / 120
            let f = CreatureLife.frame(state: .glowing, t: t, events: stamps, profile: .companion, reduceMotion: false)
            if t >= 1, t < 1.74 {
                #expect(f.sprites.allSatisfy { $0.opacity <= 1 } && f.sprites.count <= 4)
                #expect(f.sprites.allSatisfy { $0.center.y < -1 }, "a twinkle during the hop at \(t)")
            } else {
                #expect(f.sprites.count <= 1, "\(t)")
                #expect(f.sprites.allSatisfy { $0.opacity == 0.85 })
            }
        }
    }

    @Test func sleepLoopStopsAfterAMinute() {
        for (name, profile) in Self.profiles {
            let since = 10.0
            let breathing = (0..<(10 * 60)).map { CreatureLife.frame(state: .asleep, t: since + Double($0) / 60, events: [], profile: profile,
                                                                     asleepSince: since, reduceMotion: false) }
            #expect(breathing.contains { !$0.sprites.isEmpty } && breathing.contains { $0.pose.breath > 0 }, "\(name)")
            #expect(CreatureLife.needsFrames(state: .asleep, t: since + 30, events: [], profile: profile, walking: nil, asleepSince: since))
            let later = CreatureLife.frame(state: .asleep, t: since + 60.01, events: [], profile: profile, asleepSince: since, reduceMotion: false)
            #expect(later.pose == .asleep && later.sprites.isEmpty, "\(name)")
            #expect(!CreatureLife.needsFrames(state: .asleep, t: since + 60.01, events: [], profile: profile, walking: nil, asleepSince: since))
            #expect(CreatureLife.nextChange(after: since + 60.01, state: .asleep, events: [], profile: profile, walking: nil, asleepSince: since) == .infinity)
            // It stops on a whole breath: nothing jumps at the end of the loop.
            var last = CreatureLife.frame(state: .asleep, t: since + 50, events: [], profile: profile, asleepSince: since, reduceMotion: false)
            for i in 1...(11 * 240) {
                let f = CreatureLife.frame(state: .asleep, t: since + 50 + Double(i) / 240, events: [], profile: profile, asleepSince: since, reduceMotion: false)
                #expect(abs(f.pose.breath - last.pose.breath) <= 1)
                last = f
            }
        }
    }

    @Test func theSleepZFloatsOnEachBreath() {
        let z = (0..<(48 * 10)).compactMap { i -> Creature.Sprite? in
            CreatureLife.frame(state: .asleep, t: Double(i) / 100, events: [], profile: .companion, asleepSince: 0, reduceMotion: false).sprites.first
        }
        #expect(!z.isEmpty && z.allSatisfy { $0.opacity <= 0.72 + 1e-9 && $0.color == Theme.Colors.text && $0.pattern.count == 4 })
        #expect(CreatureLife.frame(state: .asleep, t: 1.99, events: [], profile: .companion, asleepSince: 0, reduceMotion: false).sprites.isEmpty)
        let born = CreatureLife.frame(state: .asleep, t: 2.01, events: [], profile: .companion, asleepSince: 0, reduceMotion: false).sprites
        #expect(born.count == 1 && abs(born[0].center.x - 15.8) < 0.05 && abs(born[0].center.y + 1.3) < 0.05)
        let high = CreatureLife.frame(state: .asleep, t: 4.59, events: [], profile: .companion, asleepSince: 0, reduceMotion: false).sprites
        #expect(high.count == 1 && abs(high[0].center.x - 17.6) < 0.05 && abs(high[0].center.y + 3.7) < 0.05)
    }

    // MARK: The walk

    @Test func theWalkRunsOnToAContactFrameThenWaves() {
        let walk = CreatureWalk(start: 1, end: 1.5)
        #expect(walk.stop.map { abs($0 - 1.6) < 1e-9 } == true)
        #expect(CreatureWalk(start: 1, end: 1.36).stop.map { abs($0 - 1.36) < 1e-9 } == true)
        // Ended just after a contact frame (1.12): the next frame boundary (1.24) is a passing frame, so it runs on to 1.36.
        #expect(CreatureWalk(start: 1, end: 1.2).stop.map { abs($0 - 1.36) < 1e-9 } == true)
        #expect(Self.pose(.awake, 1.3, walking: CreatureWalk(start: 1, end: 1.2)).raise == 1)
        #expect(CreatureWalk(start: 1).stop == nil)
        let stamps = [CreatureStamp(.accountOpened, at: 1.5)]
        // Passing frame first: the click shows at once.
        #expect(Self.pose(.awake, 1.01, walking: walk).raise == 1)
        #expect(Self.pose(.awake, 1.13, walking: walk).raise == 0)
        // Not stopped mid-step: the walk goes on to its contact frame, then the wave plays.
        let late = Self.pose(.awake, 1.55, stamps, walking: walk)
        #expect(late.raise == 1 && late.liftedLegs != [false, false, false, false])
        #expect(Self.pose(.awake, 1.66, stamps, walking: walk).armRight == .up)
        #expect(Self.pose(.awake, 1.6 + 0.02, stamps, walking: walk).raise == 0)
        #expect(Self.bodyAtRest(Self.pose(.awake, 1.6 + 0.62, stamps, walking: walk), tolerance: 1e-9))
        // Walking needs frames until its stop.
        #expect(CreatureLife.needsFrames(state: .awake, t: 1.55, events: [], profile: .companion, walking: walk, asleepSince: nil))
        #expect(!CreatureLife.needsFrames(state: .awake, t: 1.61, events: [], profile: .companion, walking: walk, asleepSince: nil))
    }

    // MARK: The schedule

    @Test func needsFramesOnlyWhileSomethingMoves() {
        let save = [CreatureStamp(.memorySaved, at: 2)]
        #expect(!CreatureLife.needsFrames(state: .awake, t: 1, events: save, profile: .companion, walking: nil, asleepSince: nil))
        #expect(CreatureLife.needsFrames(state: .awake, t: 2.1, events: save, profile: .companion, walking: nil, asleepSince: nil))
        #expect(!CreatureLife.needsFrames(state: .awake, t: 2.74, events: save, profile: .companion, walking: nil, asleepSince: nil))
        #expect(CreatureLife.needsFrames(state: .glowing, t: 9, events: [], profile: .companion, walking: nil, asleepSince: nil))
        #expect(CreatureLife.needsFrames(state: .asleep, t: 9, events: [], profile: .companion, walking: nil, asleepSince: 0))
        // A reaction still to come is a change: the schedule wakes for it.
        #expect(CreatureLife.nextChange(after: 1, state: .awake, events: save, profile: .companion, walking: nil, asleepSince: nil) <= 2)
    }

    @Test func nextChangeIsExact() {
        for (name, profile) in Self.profiles {
            var t = 0.0
            for _ in 0..<40 {
                let next = CreatureLife.nextChange(after: t, state: .awake, events: [], profile: profile, walking: nil, asleepSince: nil)
                #expect(next > t && next.isFinite, "\(name) at \(t)")
                guard next > t, next.isFinite else { break }
                let here = CreatureLife.frame(state: .awake, t: t, events: [], profile: profile, reduceMotion: false)
                var s = t
                while s < next - 1e-6 {
                    #expect(CreatureLife.frame(state: .awake, t: s, events: [], profile: profile, reduceMotion: false) == here, "\(name) changes at \(s) before \(next)")
                    s += 1.0 / 240
                }
                #expect(CreatureLife.frame(state: .awake, t: next, events: [], profile: profile, reduceMotion: false) != here, "\(name) same after \(next)")
                t = next
            }
            #expect(t > 5, "\(name) only reached \(t)")
        }
    }

    // MARK: The canvas

    @Test func spritesFitTheCanvas() {
        // Every sprite pixel inside the 24 by 19 cell canvas whose feet stand at (12, 18): grid x -4...20, y -7...12.
        // (The stage hop's upper sparkles reach 6.3 cells above the head: 6 cells of headroom would clip them.)
        let canvas = CGRect(x: 8 - Creature.canvasFeet.x, y: 11 - Creature.canvasFeet.y,
                            width: Creature.canvasCells.width, height: Creature.canvasCells.height)
        #expect(canvas == CGRect(x: -4, y: -7, width: 24, height: 19))
        func check(_ f: LifeFrame, _ label: String) {
            for s in f.sprites { #expect(canvas.contains(s.bounds), "\(label): \(s.bounds)") }
            // The body too: raised and thrown-up arms, the hop's height.
            let cells = Creature.cells(for: f.pose).map { $0.offsetBy(dx: f.pose.offset.dx, dy: f.pose.offset.dy) }
            for c in cells { #expect(canvas.contains(c), "\(label): body \(c)") }
        }
        for (name, profile) in Self.profiles {
            for e in Self.events {
                for state in [CreatureState.awake, .glowing, .asleep] {
                    let stamps = [CreatureStamp(e, at: 1)]
                    for i in 0...(240 * 1) {
                        let t = 1 + Double(i) / 240
                        check(CreatureLife.frame(state: state, t: t, events: stamps, profile: profile, reduceMotion: false), "\(name) \(e) \(state)")
                        check(CreatureLife.reducedFrame(state: state, t: t, events: stamps), "reduced \(e) \(state)")
                    }
                }
            }
            for i in 0..<(10 * 60) {
                let t = Double(i) / 60
                check(CreatureLife.frame(state: .asleep, t: t, events: [], profile: profile, asleepSince: 0, reduceMotion: false), "\(name) asleep")
                check(CreatureLife.frame(state: .glowing, t: t, events: [], profile: profile, reduceMotion: false), "\(name) glowing")
                check(CreatureLife.frame(state: .awake, t: t, events: [], profile: profile, walking: CreatureWalk(start: 0), reduceMotion: false), "\(name) walk")
            }
        }
    }
}
