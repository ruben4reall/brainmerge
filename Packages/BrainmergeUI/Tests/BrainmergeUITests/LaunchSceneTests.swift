import CoreGraphics
import Foundation
import Testing
@testable import BrainmergeUI

/// The launch as pure functions of time: key frames, hand-off rules, continuity, Reduce Motion, and the same leap at the
/// end of the guided setup.
@Suite struct LaunchSceneTests {
    let size = CGSize(width: 960, height: 640)
    /// The sidebar footer's creature (2 pt cells), low on the left: the usual landing.
    let sidebar = LaunchTarget(feet: CGPoint(x: 48, y: 612), unit: 2, asleep: false)
    /// The welcome creature of a first run (4 pt cells), 150 pt higher than the splash's feet.
    var welcome: LaunchTarget { LaunchTarget(feet: CGPoint(x: 480, y: AssembleScene.splashFeet(in: size).y - 150), unit: 4, asleep: false) }

    func input(_ ready: Double?, skip: Double? = nil, reduce: Bool = false, asleep: Bool = false, target: LaunchTarget?? = .none) -> LaunchInput {
        var landing = target ?? sidebar
        if asleep { landing?.asleep = true }
        return LaunchInput(size: size, readyAt: ready, skippedAt: skip, target: landing, reduceMotion: reduce)
    }

    static func finite(_ f: LaunchFrame) -> Bool {
        let p = f.pose
        let numbers: [Double] = [f.feet.x, f.feet.y, f.unit, f.shadowOpacity, f.shadowInset, f.wordmarkOpacity, f.wordmarkRise,
                                 f.wordmarkBlur, f.captionOpacity, f.screensOpacity, f.screensScale, f.guideOpacity,
                                 p.offset.dx, p.offset.dy, p.scaleX, p.scaleY, p.rotation, p.eyeHeight, p.eyeBottom, p.opacity]
            + (p.pixels ?? []).flatMap { [$0.dx, $0.dy, $0.scale, $0.opacity] }
        return numbers.allSatisfy(\.isFinite)
    }

    /// The gather's pixels, equal to floating-point noise (a time read back from a sum is not exact).
    static func same(_ a: [PixelState]?, _ b: [PixelState]?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.count == b.count && zip(a, b).allSatisfy {
            abs($0.dx - $1.dx) < 1e-6 && abs($0.dy - $1.dy) < 1e-6 && abs($0.scale - $1.scale) < 1e-6 && abs($0.opacity - $1.opacity) < 1e-6
        }
    }

    /// Eye heights are whole steps: open, half, the blink's slit, or the asleep dash on its own row.
    static func eyesInSteps(_ pose: Creature.Pose) -> Bool {
        if pose.eyeHeight == Creature.Pose.asleep.eyeHeight { return pose.eyeBottom == Creature.Pose.asleep.eyeBottom }
        return [0, 0.15, 0.5, 1].contains(pose.eyeHeight) && pose.eyeBottom == Creature.Pose.rest.eyeBottom
    }

    // MARK: Ported from the prototype

    @Test func theHeroStillIsTheRestGridOnWholePoints() {
        let f = AssembleScene.frame(at: AssembleScene.heroTime, input(nil))
        #expect(f.pose == .rest)
        #expect(f.wordmarkOpacity > 0.999 && f.wordmarkRise == 0 && f.wordmarkBlur == 0)
        #expect(f.captionOpacity == 0 && f.screensOpacity == 0 && f.shadowOpacity == 1 && f.shadowInset == 0)
        let originX = f.feet.x - 8 * f.unit, originY = f.feet.y - 11 * f.unit
        #expect(originX == originX.rounded() && originY == originY.rounded())
        #expect(f.feet == AssembleScene.splashFeet(in: size) && f.unit == Theme.Launch.unit)
    }

    @Test func theBeatEndsExactlyAtRestBeforeTheWalk() {
        for t in [AssembleScene.idleStart - 0.001, AssembleScene.assembled + 0.001] {
            let pose = AssembleScene.beat(at: t, size: size).pose
            #expect(pose.pixels == nil && pose.eyeHeight > 0, "t = \(t)")
        }
        #expect(AssembleScene.beat(at: AssembleScene.idleStart - 0.001, size: size).pose == .rest)
        // Contact frames of the walk are the rest grid too, passing frames are the app's walk with the arm swing.
        let contact = AssembleScene.idleStart + LaunchDirector.walkFrame * 1.5
        #expect(AssembleScene.walkIndex(at: contact) % 2 == 0)
        #expect(AssembleScene.beat(at: contact, size: size).pose == .rest)
        let passing = AssembleScene.beat(at: AssembleScene.idleStart + 0.01, size: size)
        #expect(passing.pose == Creature.walkFrame(1) && passing.shadowInset == 1)
    }

    @Test func theHandOffWaitsForReadyAndTheMinimumUnlessSkipped() {
        #expect(LaunchDirector.handoffStart(readyAt: nil, skippedAt: 0.1) == nil)
        #expect(LaunchDirector.handoffStart(readyAt: 0.1, skippedAt: nil) == AssembleScene.minimumVisible)
        #expect(AssembleScene.minimumVisible == 0.48)
        #expect(LaunchDirector.handoffStart(readyAt: 0.1, skippedAt: 0.2) == 0.2)
        #expect(LaunchDirector.handoffStart(readyAt: 0.9, skippedAt: nil) == 0.9)
        // A skip before ready changes nothing; a late click never moves a hand-off already decided.
        #expect(LaunchDirector.handoffStart(readyAt: 0.9, skippedAt: 0.2) == 0.9)
        #expect(LaunchDirector.handoffStart(readyAt: 0.3, skippedAt: 0.6) == 0.48)
        // During the walk: the next contact frame, at most two frames later.
        for ready in stride(from: 1.53, to: 3.0, by: 0.037) {
            let hs = LaunchDirector.handoffStart(readyAt: ready, skippedAt: nil)!
            #expect(hs >= ready && hs - ready <= 2 * LaunchDirector.walkFrame + 1e-9)
            #expect(AssembleScene.walkIndex(at: hs + 0.001) % 2 == 0)
            #expect(AssembleScene.beat(at: hs, size: size).pose == .rest)
        }
    }

    @Test func theLeapEndsOnTheTargetAtRestOrAsleep() {
        for asleep in [false, true] {
            for target in [sidebar, welcome] {
                let inp = input(0.2, asleep: asleep, target: target)
                let hs = LaunchDirector.handoffStart(readyAt: 0.2, skippedAt: nil)!
                let f = AssembleScene.frame(at: hs + 3, inp)
                #expect(f.finished && f.screensOpacity == 1 && f.screensScale == 1)
                #expect(f.feet == target.feet && f.unit == target.unit)
                #expect(f.pose == (asleep ? .asleep : .rest))
                #expect(f.shadowOpacity == 0 && f.wordmarkOpacity == 0 && f.captionOpacity == 0)
                // The overlay goes exactly when the creature is still: 1.08 s after the hand-off awake, 1.44 s asleep.
                let end = hs + (asleep ? 1.44 : 1.08)
                #expect(LaunchDirector.finishTime(inp).map { abs($0 - end) < 1e-9 } == true)
                #expect(!AssembleScene.frame(at: end - 0.001, inp).finished && AssembleScene.frame(at: end + 1e-9, inp).finished)
                #expect(AssembleScene.frame(at: end + 1e-9, inp).pose == (asleep ? .asleep : .rest))
            }
        }
    }

    @Test func nothingJumpsFromFrameToFrame() {
        // At 120 Hz the feet never move more than 20 pt, the cell never changes by more than 0.25 pt.
        for target in [sidebar, welcome] {
            for ready in [0.05, 0.3, 0.8, 0.95, 1.05, 1.7, 2.33] {
                for skip in [nil, 0.2] as [Double?] {
                    let inp = input(ready, skip: skip, target: target)
                    var prev = AssembleScene.frame(at: 0, inp)
                    for i in 1...480 {
                        let f = AssembleScene.frame(at: Double(i) / 120, inp)
                        #expect(hypot(f.feet.x - prev.feet.x, f.feet.y - prev.feet.y) <= 20, "ready \(ready) skip \(String(describing: skip)) i \(i)")
                        #expect(abs(f.unit - prev.unit) <= 0.25)
                        prev = f
                    }
                }
            }
        }
    }

    @Test func reduceMotionOnlyFades() {
        let inp = input(0.2, reduce: true)
        let feet = AssembleScene.splashFeet(in: size)
        for i in 0...120 {
            let t = Double(i) / 60
            let f = AssembleScene.frame(at: t, inp)
            var still = f.pose
            still.opacity = 1
            #expect(still == .rest, "t = \(t)")
            #expect(f.feet == feet && f.unit == Theme.Launch.unit && f.screensScale == 1 && f.wordmarkRise == 0 && f.wordmarkBlur == 0)
            #expect(f.shadowInset == 0)
        }
        #expect(abs(AssembleScene.frame(at: 0.075, inp).pose.opacity - 0.5) < 1e-9)
        #expect(AssembleScene.frame(at: 0.15, inp).wordmarkOpacity == 1)
        #expect(!AssembleScene.frame(at: 0.48 + 0.149, inp).finished)
        #expect(AssembleScene.frame(at: 0.48 + 0.15, inp).finished)
        #expect(AssembleScene.frame(at: 0.48 + 0.15, inp).screensOpacity == 1)
        #expect(LaunchDirector.finishTime(inp).map { abs($0 - 0.63) < 1e-9 } == true)
        // "Waking up…" at 2 s, in 0.15 s.
        let slow = input(3, reduce: true)
        #expect(AssembleScene.frame(at: 1.99, slow).captionOpacity == 0 && AssembleScene.frame(at: 2.151, slow).captionOpacity == 1)
    }

    @Test func eyesAndArmsMoveInWholeSteps() {
        for target in [sidebar, welcome] {
            for asleep in [false, true] {
                for ready in [0.2, 0.95, 2.2] {
                    for i in 0...400 {
                        let f = AssembleScene.frame(at: Double(i) / 100, input(ready, asleep: asleep, target: target))
                        #expect(Self.eyesInSteps(f.pose), "t \(Double(i) / 100): \(f.pose.eyeHeight) \(f.pose.eyeBottom)")
                        #expect([ArmPose.rest, .lift1].contains(f.pose.armLeft) && [ArmPose.rest, .lift1].contains(f.pose.armRight))
                        #expect([-1, 0, 1].contains(f.pose.look) && [0, 1].contains(f.pose.raise))
                    }
                }
            }
        }
    }

    // MARK: The beat table, key frame by key frame (MOTION.md 3.2)

    @Test func theBeatTableHoldsItsValues() {
        let ground = AssembleScene.splashFeet(in: size).y
        let slow = input(nil)   // never ready: the splash alone
        // The ghost is in place at once; the rim pixels wait for the inner ones (stagger 0.14 s over the radius).
        let homes = Creature.bodyPixels(), center = CGPoint(x: 8, y: 5.5)
        let rim = homes.indices.max { hypot(Double(homes[$0].x) + 0.5 - center.x, Double(homes[$0].y) + 0.5 - center.y)
                                      < hypot(Double(homes[$1].x) + 0.5 - center.x, Double(homes[$1].y) + 0.5 - center.y) }!
        let spread = Theme.Launch.gatherSpread + 0.25 * Dice.hash01(homes[rim].x, homes[rim].y, 7)
        let hx = Double(homes[rim].x) + 0.5 - center.x
        let early = AssembleScene.frame(at: 0.179, slow).pose.pixels!
        #expect(abs(early[rim].dx - hx * (spread - 1)) < 1e-9, "the rim pixel has not started at 0.179 s")
        // The shadow comes in from 0.18 s.
        #expect(AssembleScene.frame(at: 0.179, slow).shadowOpacity == 0 && AssembleScene.frame(at: 0.19, slow).shadowOpacity > 0)
        // The click at 0.44: a squash from the feet.
        #expect(AssembleScene.frame(at: 0.47, slow).pose.scaleY < 0.99 && AssembleScene.frame(at: 0.47, slow).pose.scaleX > 1)
        // The wordmark from 0.52: rising 8 pt and sharpening from a 1.5 pt blur.
        let word = AssembleScene.frame(at: 0.52, slow)
        #expect(AssembleScene.frame(at: 0.519, slow).wordmarkOpacity == 0 && AssembleScene.frame(at: 0.53, slow).wordmarkOpacity > 0)
        #expect(word.wordmarkRise == 8 && word.wordmarkBlur == 1.5)
        // The hop: 2.4 cells of 7 pt at its middle (0.97 s).
        #expect(abs(AssembleScene.frame(at: 0.97, slow).feet.y - (ground - 2.4 * 7)) < 1e-6)
        // "Waking up…" at 2.0 s.
        #expect(AssembleScene.frame(at: 1.999, slow).captionOpacity == 0 && AssembleScene.frame(at: 2.05, slow).captionOpacity > 0)
    }

    @Test func theLandingRingsDownBeforeItRests() throws {
        // The touchdown squash settles once its ringing stays under 0.004, not the first time it crosses zero.
        let leap = Leap(start: .rest, feet: AssembleScene.splashFeet(in: size), unit: 7, startVelocityY: 0, target: sidebar)
        let crossing = stride(from: 0.0, to: Leap.settled, by: 1.0 / 2000).first { tl in
            let d = Leap.landing.displacement(tl, from: -Leap.squash)
            return abs(d) < 0.004 && abs(d) > 1e-6
        }
        let tl = try #require(crossing)
        #expect(tl < Leap.settled)
        #expect(leap.frame(at: leap.touchdown + tl).pose.scaleY != 1, "snapped to rest at a zero crossing, \(tl) s after touchdown")
        #expect(leap.frame(at: leap.touchdown + Leap.settled).pose.scaleY == 1)
    }

    // MARK: The director's changes

    @Test func theCreatureIsNeverEyelessOnceWhole() {
        // Before the click the pixels are still gathering: no eyes on a cloud. From the click on, always eyes: the asleep
        // dash, then half, then open.
        #expect(AssembleScene.beat(at: 0.43, size: size).pose.eyeHeight == 0)
        let click = AssembleScene.beat(at: 0.44, size: size).pose
        #expect(click.eyeHeight == Creature.Pose.asleep.eyeHeight && click.eyeBottom == Creature.Pose.asleep.eyeBottom)
        #expect(AssembleScene.beat(at: 0.54, size: size).pose.eyeHeight == 0.5)
        #expect(AssembleScene.beat(at: 0.60, size: size).pose.eyeHeight == 1)
        for target in [sidebar, welcome, nil] as [LaunchTarget?] {
            for ready in [nil, 0.05, 0.3, 0.6, 0.95, 1.7] as [Double?] {
                for skip in [nil, 0.1] as [Double?] {
                    let inp = input(ready, skip: skip, target: .some(target))
                    for i in 0...480 {
                        let t = 0.44 + Double(i) / 120
                        let f = AssembleScene.frame(at: t, inp)
                        guard f.pose.opacity > 0 else { continue }
                        #expect(f.pose.eyeHeight > 0, "ready \(String(describing: ready)) skip \(String(describing: skip)) t \(t)")
                    }
                }
            }
        }
    }

    @Test func theLeapReachesATargetAboveTheStart() {
        // The prototype took a square root of a negative number here: the welcome creature sits higher than the splash.
        let start = AssembleScene.splashFeet(in: size)
        let leap = Leap(start: .rest, feet: start, unit: Theme.Launch.unit, startVelocityY: 0, target: welcome)
        let (vy, g) = leap.ballistics
        #expect(vy.isFinite && g.isFinite && vy < 0 && g > 0)
        var highest = CGFloat.infinity
        for i in 0...Int(leap.end * 240) {
            let (pose, feet, unit) = leap.frame(at: Double(i) / 240)
            #expect(feet.x.isFinite && feet.y.isFinite && unit.isFinite && pose.scaleY.isFinite)
            highest = min(highest, feet.y)
        }
        // The apex is 12 pt above the higher end (here the target), and the creature lands exactly on it.
        #expect(abs(highest - (welcome.feet.y - Theme.Launch.leapApex)) < 0.5)
        let landed = leap.frame(at: leap.touchdown)
        #expect(landed.feet == welcome.feet && landed.unit == welcome.unit)
        // A lower target keeps the apex 12 pt above the start.
        let down = Leap(start: .rest, feet: start, unit: Theme.Launch.unit, startVelocityY: 0, target: sidebar)
        let low = (0...240).map { down.frame(at: Double($0) / 240).feet.y }.min()!
        #expect(abs(low - (start.y - Theme.Launch.leapApex)) < 0.5)
    }

    @Test func aLeapFromTheAirNeverFallsUpward() {
        // Mid-hop the leap keeps the height and the vertical speed, and never needs gravity pointing up. When the speed it
        // has cannot carry it there under a natural gravity (a higher target), it does not leap from the air at all.
        let start = CGPoint(x: 480, y: 320)
        for v0 in [-220.0, -80, 0.5, 80, 220] as [CGFloat] {
            for target in [sidebar, welcome] {
                let leap = Leap(start: .rest, feet: start, unit: Theme.Launch.unit, startVelocityY: v0, target: target)
                #expect(leap.ballistics.g > 0, "v0 \(v0) target \(target.feet)")
                #expect(leap.frame(at: 0).feet == start)
                #expect(leap.frame(at: leap.touchdown).feet == target.feet)
                if leap.keepsItsSpeed { #expect(leap.ballistics.vy == v0) }
            }
            #expect(!Leap(start: .rest, feet: start, unit: Theme.Launch.unit, startVelocityY: v0, target: welcome).keepsItsSpeed)
        }
        // Going down to the sidebar, the arc keeps the speed it had: no kink.
        let keep = Leap(start: .rest, feet: start, unit: Theme.Launch.unit, startVelocityY: 80, target: sidebar)
        #expect(keep.takeoff == 0 && keep.keepsItsSpeed && keep.ballistics.vy == 80)
    }

    /// A hand-off mid-hop never kicks the creature up again in the air: it keeps the hop's vertical speed, either on the
    /// leap's own arc or, when no natural arc starts from there (a higher target, the end of the hop), by finishing its hop
    /// and leaping from the landing, the landing's squash for a crouch.
    @Test func aHandOffMidHopKeepsTheHopsVerticalSpeed() throws {
        let ground = AssembleScene.splashFeet(in: size).y
        let dt = 1.0 / 240
        for target in [sidebar, welcome] {
            for ready in stride(from: 0.83, through: 1.11, by: 0.02) {
                let inp = input(ready, target: target)
                let hs = try #require(LaunchDirector.handoffStart(readyAt: ready, skippedAt: nil))
                let finish = try #require(LaunchDirector.finishTime(inp))
                let touchdown = finish - 0.50
                var t = hs - 3 * dt
                while t + dt < touchdown {
                    let y0 = AssembleScene.frame(at: t - dt, inp).feet.y, y1 = AssembleScene.frame(at: t, inp).feet.y
                    let y2 = AssembleScene.frame(at: t + dt, inp).feet.y
                    if max(y0, y1, y2) < ground - 0.5 {
                        // In the air, gravity only ever pulls down: the speed never jumps upward.
                        #expect(y2 - 2 * y1 + y0 > -0.05, "\(target.feet) ready \(ready) t \(t): \(y0) \(y1) \(y2)")
                    }
                    t += dt
                }
                // Right after the hand-off, the path is the hop's own: same height, same speed.
                let hop0 = AssembleScene.beat(at: hs, size: size).feet.y, hop1 = AssembleScene.beat(at: hs + dt, size: size).feet.y
                let leap0 = AssembleScene.frame(at: hs, inp).feet.y, leap1 = AssembleScene.frame(at: hs + dt, inp).feet.y
                #expect(abs(leap0 - hop0) < 1e-9 && abs((leap1 - leap0) - (hop1 - hop0)) < 0.1, "\(target.feet) ready \(ready)")
            }
        }
    }

    @Test func everyFrameIsFinite() {
        for target in [sidebar, welcome, nil] as [LaunchTarget?] {
            for ready in [nil, 0.0, 0.05, 0.3, 0.8, 0.95, 1.05, 1.47, 1.7, 2.33] as [Double?] {
                for skip in [nil, 0.0, 0.2] as [Double?] {
                    for reduce in [false, true] {
                        let inp = input(ready, skip: skip, reduce: reduce, target: .some(target))
                        for i in 0...600 {
                            let f = AssembleScene.frame(at: Double(i) / 120, inp)
                            #expect(Self.finite(f), "ready \(String(describing: ready)) t \(Double(i) / 120)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Hand-off details

    @Test func aFastLaunchShowsTheScreensUnderTheLeap() {
        // Ready well before 0.48 s: the leap starts at 0.48, the screens are fully in at 0.82 s, the creature lands at 1.06 s.
        let inp = input(0.2)
        #expect(AssembleScene.frame(at: 0.479, inp).screensOpacity == 0 && !AssembleScene.frame(at: 0.479, inp).handingOff)
        let first = AssembleScene.frame(at: 0.48, inp)
        #expect(first.handingOff && first.screensOpacity == 0 && abs(first.screensScale - 0.985) < 1e-9)
        #expect(AssembleScene.frame(at: 0.515, inp).screensOpacity == 0)
        #expect(AssembleScene.frame(at: 0.60, inp).screensOpacity > 0.5)
        #expect(AssembleScene.frame(at: 0.8201, inp).screensOpacity == 1 && AssembleScene.frame(at: 0.8201, inp).screensScale == 1)
        #expect(AssembleScene.frame(at: 0.8199, inp).screensOpacity > 0.999)
        let landed = AssembleScene.frame(at: 1.06, inp)
        #expect(landed.feet == sidebar.feet && landed.unit == sidebar.unit)
        #expect(AssembleScene.frame(at: 1.05, inp).feet != sidebar.feet)
        // The wordmark and caption go in 0.16 s, the shadow from 0.04 to 0.20 with 3 more cells of inset.
        #expect(AssembleScene.frame(at: 0.64, inp).wordmarkOpacity == 0 && AssembleScene.frame(at: 0.64, inp).captionOpacity == 0)
        #expect(AssembleScene.frame(at: 0.68, inp).shadowOpacity == 0)
        #expect(AssembleScene.frame(at: 0.68, inp).shadowInset == AssembleScene.beat(at: 0.48, size: size).shadowInset + 3)
    }

    @Test func theLeapCrouchesThenLeansAndLooksTowardItsHome() {
        let inp = input(0.2)
        let crouch = AssembleScene.frame(at: 0.48 + 0.079, inp).pose
        #expect(abs(crouch.scaleY - 0.86) < 1e-3 && abs(crouch.scaleX - 1.08) < 1e-3 && crouch.eyeHeight == 0.5)
        let mid = AssembleScene.frame(at: 0.48 + 0.08 + 0.25, inp)
        #expect(mid.pose.rotation < 0 && mid.pose.look == -1 && mid.pose.legsTucked)
        #expect(mid.pose.armLeft == .lift1 && mid.pose.armRight == .lift1)
        #expect(mid.unit < Theme.Launch.unit && mid.unit > sidebar.unit)
        // Touchdown squashes from 0.80, then the eyes come back to center at 0.76 and blink from 0.88 to 1.02.
        let touch = AssembleScene.frame(at: 0.48 + 0.58, inp).pose
        #expect(abs(touch.scaleY - 0.80) < 1e-9 && touch.rotation == 0 && touch.look == -1)
        #expect(AssembleScene.frame(at: 0.48 + 0.76, inp).pose.look == 0)
        #expect(AssembleScene.frame(at: 0.48 + 0.89, inp).pose.eyeHeight == 0.5)
        #expect(AssembleScene.frame(at: 0.48 + 0.95, inp).pose.eyeHeight == 0.15)
        #expect(AssembleScene.frame(at: 0.48 + 1.03, inp).pose.eyeHeight == 1)
    }

    @Test func aSkipDuringTheGatherFinishesItAtThreeTimesItsSpeedInsideTheCrouch() throws {
        // Ready at once, a click at 0.1 s: the gather runs three times faster from the hand-off, and the crouch lasts until
        // it is whole (0.48 s of gather left: 0.16 s). No flight on a cloud of pixels.
        let feet = AssembleScene.splashFeet(in: size)
        for (ready, skip, crouch) in [(0.05, 0.1, 0.16), (0.02, 0.0, (0.58 - 0.02) / 3), (0.3, 0.35, 0.08)] {
            let inp = input(ready, skip: skip)
            let hs = try #require(LaunchDirector.handoffStart(readyAt: ready, skippedAt: skip))
            #expect(hs == max(ready, skip))
            for i in 0..<Int(crouch * 240) {
                let tau = Double(i) / 240
                let f = AssembleScene.frame(at: hs + tau, inp)
                #expect(Self.same(f.pose.pixels, AssembleScene.pixelStates(at: hs + 3 * tau)), "skip \(skip) tau \(tau)")
                #expect(f.feet == feet && !f.pose.legsTucked, "skip \(skip) tau \(tau): no takeoff inside the crouch")
                // No eyes on a cloud: they come with the click (0.44 s of gather), as in the beat.
                #expect((f.pose.eyeHeight == 0) == (hs + 3 * tau < 0.44 - 1e-9), "skip \(skip) tau \(tau): eyes \(f.pose.eyeHeight)")
            }
            let takeoff = AssembleScene.frame(at: hs + crouch + 1e-6, inp)
            #expect(takeoff.pose.pixels == nil && takeoff.pose.eyeHeight > 0, "skip \(skip)")
            #expect(AssembleScene.frame(at: hs + crouch + 0.05, inp).feet != feet, "skip \(skip): the leap takes off once whole")
            #expect(LaunchDirector.finishTime(inp).map { abs($0 - (hs + crouch + 0.50 + 0.50)) < 1e-9 } == true, "skip \(skip)")
        }
    }

    @Test func withNoTargetTheCreatureHopsInPlaceAndFades() {
        // Nowhere to go: the splash's own hop (2.4 cells, 0.30 s in the air: the same gravity), then a 0.2 s fade.
        let inp = input(0.2, target: .some(nil))
        let feet = AssembleScene.splashFeet(in: size)
        var highest = feet.y, air = 0
        for i in 0...240 {
            let f = AssembleScene.frame(at: 0.48 + Double(i) / 240, inp)
            #expect(f.feet.x == feet.x && f.unit == Theme.Launch.unit && f.pose.rotation == 0 && f.pose.look == 0)
            highest = min(highest, f.feet.y)
            if f.feet.y < feet.y { air += 1 }
        }
        #expect(abs(highest - (feet.y - 2.4 * Theme.Launch.unit)) < 0.3, "apex \(feet.y - highest) pt")
        #expect(abs(Double(air) / 240 - 0.30) < 0.01, "\(Double(air) / 240) s in the air")
        let touchdown = 0.48 + 0.08 + 0.30
        #expect(AssembleScene.frame(at: touchdown - 0.001, inp).pose.opacity == 1)
        #expect(AssembleScene.frame(at: touchdown + 0.1, inp).pose.opacity < 1)
        let gone = AssembleScene.frame(at: touchdown + 0.2 + 1e-9, inp)
        #expect(gone.pose.opacity == 0 && gone.finished && gone.screensOpacity == 1)
        #expect(LaunchDirector.finishTime(inp).map { abs($0 - (touchdown + 0.2)) < 1e-9 } == true)
        // Already hopping at the hand-off: that hop is the one, it lands at 1.12 s and the creature fades from there.
        let midHop = input(0.95, target: .some(nil))
        for t in stride(from: 0.95, to: AssembleScene.hopLand, by: 1.0 / 240) {
            #expect(AssembleScene.frame(at: t, midHop).feet == AssembleScene.beat(at: t, size: size).feet, "t \(t)")
        }
        #expect(LaunchDirector.finishTime(midHop).map { abs($0 - (AssembleScene.hopLand + 0.2)) < 1e-9 } == true)
    }

    @Test func theSplashShadowSitsOnWholePointsUnderTheFeet() {
        let feet = AssembleScene.splashFeet(in: size)
        for inset in [0, 0.35, 1, 2.7, 6] as [CGFloat] {
            let r = AssembleScene.shadowRect(feet: feet, inset: inset)
            #expect(r.minX == r.minX.rounded() && r.maxX == r.maxX.rounded() && r.minY == feet.y && r.height == Theme.Launch.unit)
            #expect(abs(r.midX - feet.x) <= 0.5)
        }
        #expect(AssembleScene.shadowRect(feet: feet, inset: 0).width == 12 * Theme.Launch.unit)
        #expect(AssembleScene.shadowRect(feet: feet, inset: 6).width >= Theme.Launch.unit)
    }

    // MARK: A way through empty space

    /// The real window at 960 by 640 with four accounts (measured on the hosted RootView): the sidebar's words and its
    /// rows' orbs, names and hints down to 383, the Accounts header and cards down to 256, the creature's line right of
    /// its landing spot.
    let footer = LaunchTarget(feet: CGPoint(x: 42, y: 618), unit: 2, asleep: true)
    let busy = [CGRect(x: 20, y: 40, width: 206, height: 200), CGRect(x: 30, y: 249, width: 186, height: 134),
                CGRect(x: 264, y: 20, width: 666, height: 236), CGRect(x: 66, y: 598, width: 100, height: 18)]

    /// The creature's cells where they are drawn: squashed, stretched and leaning around the middle of its feet.
    static func bodyCells(_ f: LaunchFrame) -> [CGRect] {
        let g = Creature.geometry(for: f.pose, feet: f.feet, unit: f.unit, displayScale: 2)
        let transform = CGAffineTransform(translationX: g.anchor.x, y: g.anchor.y)
            .rotated(by: f.pose.rotation * .pi / 180).scaledBy(x: f.pose.scaleX, y: f.pose.scaleY)
            .translatedBy(x: -g.anchor.x, y: -g.anchor.y)
        return g.body.map { $0.rect.applying(transform) }
    }
    static func covers(_ f: LaunchFrame, _ obstacle: CGRect) -> Bool { bodyCells(f).contains { $0.intersects(obstacle) } }

    @Test func theLaunchLeapGoesThroughEmptySpace() throws {
        // The spec's arc crosses the account rows here: another shape of leap finds the way below them and comes down on
        // the footer from above, never over its line.
        let natural = input(0.2, target: footer)
        let crossed = (0...240).contains { i in
            let f = AssembleScene.frame(at: 0.56 + Double(i) / 480, natural)
            return busy.contains { Self.covers(f, $0) }
        }
        #expect(crossed, "the natural arc should cross the rows in this window")
        let inp = LaunchInput(size: size, readyAt: 0.2, target: footer, obstacles: busy)
        let finish = try #require(LaunchDirector.finishTime(inp))
        for i in 0...Int((finish - 0.48) * 480) {
            let t = 0.48 + Double(i) / 480
            let f = AssembleScene.frame(at: t, inp)
            for o in busy { #expect(!Self.covers(f, o), "t \(t): feet \(f.feet) over \(o)") }
        }
        let landed = AssembleScene.frame(at: finish, inp)
        #expect(landed.feet == footer.feet && landed.unit == footer.unit && landed.pose == .asleep && landed.finished)
        // The same timing: only the shape changes.
        #expect(LaunchDirector.finishTime(natural) == finish)
    }

    @Test func withNothingInTheWayTheLeapKeepsItsNaturalArc() {
        let start = AssembleScene.splashFeet(in: size)
        let natural = Leap(start: .rest, feet: start, unit: 7, startVelocityY: 0, target: footer)
        #expect(natural.route == .natural)
        #expect(Leap.routed(start: .rest, feet: start, unit: 7, startVelocityY: 0, target: footer, avoiding: []).route == .natural)
        // Out of the way (the top right corner): still the natural arc.
        let far = [CGRect(x: 800, y: 0, width: 160, height: 60)]
        #expect(Leap.routed(start: .rest, feet: start, unit: 7, startVelocityY: 0, target: footer, avoiding: far).route == .natural)
        #expect(LeapRoute.natural.apex == Theme.Launch.leapApex && LeapRoute.natural.travel == Ease.travel)
    }

    @Test func whenNoWayIsClearTheLeapTakesTheLeastCovered() {
        // A wall of text between the splash and the sidebar: no shape of leap clears it; the one chosen covers the least.
        let start = AssembleScene.splashFeet(in: size)
        let wall = [CGRect(x: 200, y: 0, width: 60, height: 640), CGRect(x: 0, y: 380, width: 960, height: 40)]
        let chosen = Leap.routed(start: .rest, feet: start, unit: 7, startVelocityY: 0, target: footer, avoiding: wall)
        for route in LeapRoute.candidates {
            let other = Leap(start: .rest, feet: start, unit: 7, startVelocityY: 0, target: footer, route: route)
            #expect(chosen.cover(wall) <= other.cover(wall) + 1e-9)
        }
        #expect(chosen.cover(wall) > 0)
        #expect(chosen.frame(at: chosen.touchdown).feet == footer.feet)
    }

    /// A crowded window (eight accounts at 960 by 640): the cards cover the splash's own spot and the rows fill the sidebar,
    /// so no leap can stay clear. The screens then wait for the landing: the creature flies over the empty window, and the
    /// screens come in around it once it is home. Until then the splash keeps the clicks (nothing to click is visible).
    @Test func whenNoWayIsClearTheScreensWaitForTheLanding() throws {
        let crowded = [CGRect(x: 20, y: 40, width: 206, height: 200), CGRect(x: 30, y: 249, width: 186, height: 270),
                       CGRect(x: 264, y: 20, width: 666, height: 418), CGRect(x: 66, y: 598, width: 100, height: 18)]
        let inp = LaunchInput(size: size, readyAt: 0.2, target: footer, obstacles: crowded)
        let touchdown = 0.48 + 0.08 + 0.50
        for i in 0..<Int((touchdown - 0.48) * 240) {
            let f = AssembleScene.frame(at: 0.48 + Double(i) / 240, inp)
            #expect(f.screensOpacity == 0 && f.screensHeld && f.handingOff, "t \(0.48 + Double(i) / 240)")
        }
        let after = AssembleScene.frame(at: touchdown + 0.15, inp)
        #expect(after.screensOpacity > 0.5 && after.screensOpacity < 1 && !after.screensHeld)
        #expect(AssembleScene.frame(at: touchdown + 0.30 + 1e-6, inp).screensOpacity == 1)
        #expect(LaunchDirector.finishTime(inp) == LaunchDirector.finishTime(input(0.2, target: footer)))
        // A clear way: the screens come in under the leap, as always.
        let clear = LaunchInput(size: size, readyAt: 0.2, target: footer, obstacles: busy)
        #expect(AssembleScene.frame(at: 0.60, clear).screensOpacity > 0.5 && !AssembleScene.frame(at: 0.60, clear).screensHeld)
        // The guide's last leap too.
        let byTheButton = LaunchTarget(feet: CGPoint(x: 381, y: 571), unit: 3, asleep: false)
        let wall = crowded + [CGRect(x: 0, y: 450, width: 960, height: 140)]
        #expect(GuideExit.frame(at: 0.3, from: byTheButton, to: footer, obstacles: wall, reduceMotion: false).screensOpacity == 0)
        #expect(GuideExit.frame(at: 0.3, from: byTheButton, to: footer, obstacles: busy, reduceMotion: false).screensOpacity > 0.99)
    }

    /// The same window as the hosted RootView reports it now that each card marks only its words, orb and buttons (four
    /// accounts at 960 by 640): the header, the cards' insides (their empty edges are free), the sidebar's words, its four
    /// rows down to 383.5, the creature's line.
    let fourAccounts = [
        CGRect(x: 264, y: 20, width: 676, height: 50), CGRect(x: 278, y: 100, width: 304, height: 51),
        CGRect(x: 622, y: 100, width: 304, height: 51), CGRect(x: 278, y: 191, width: 304, height: 51),
        CGRect(x: 622, y: 191, width: 304, height: 51), CGRect(x: 30, y: 50, width: 82.5, height: 17),
        CGRect(x: 20, y: 79, width: 204, height: 30.5), CGRect(x: 20, y: 113.5, width: 204, height: 31),
        CGRect(x: 20, y: 148.5, width: 204, height: 30), CGRect(x: 20, y: 182.5, width: 204, height: 30),
        CGRect(x: 30, y: 259.5, width: 184, height: 22), CGRect(x: 30, y: 293.5, width: 184, height: 22),
        CGRect(x: 30, y: 327.5, width: 184, height: 22), CGRect(x: 30, y: 361.5, width: 184, height: 22),
        CGRect(x: 66, y: 599.5, width: 100, height: 15)]
    /// The same window with the header and cards as one block, down to the cards' empty bottom edges (256): the splash's
    /// hop reaches into it.
    var fourAccountsAsABlock: [CGRect] { [CGRect(x: 264, y: 20, width: 676, height: 236)] + fourAccounts.filter { $0.maxX < 240 } }

    @Test func whenTheRowsReachLowTheLeapRisesFirstThenSwingsHome() throws {
        // Every arc that moves over at once crosses the sidebar's fourth row. The leap keeps its push and its stretch (never
        // the dive that slides off the splash): straight up to its apex, then it swings home past the rows.
        let inp = LaunchInput(size: size, readyAt: 0.2, target: footer, obstacles: fourAccounts)
        let plan = try #require(LaunchDirector.handoff(inp))
        let leap = try #require(plan.leap)
        #expect(leap.route.apex == Theme.Launch.leapApex && leap.route.stretch == 1 && leap.route.lag > 0, "\(leap.route)")
        #expect(!plan.held && leap.cover(fourAccounts) == 0)
        let splash = AssembleScene.splashFeet(in: size)
        let swing = leap.takeoff + leap.route.lag * leap.flightTime
        var highest = CGFloat.infinity
        for i in 0...Int(leap.flightTime * 480) {
            let tau = leap.takeoff + Double(i) / 480
            let feet = leap.frame(at: tau).feet
            if tau <= swing { #expect(feet.x == splash.x, "tau \(tau): \(feet.x)") }
            highest = min(highest, feet.y)
        }
        #expect(abs(highest - (splash.y - Theme.Launch.leapApex)) < 0.5, "apex \(splash.y - highest) pt")
        // It moves over from rest: no kink where the swing starts.
        let a = leap.frame(at: swing + 1.0 / 480).feet.x, b = leap.frame(at: swing + 2.0 / 480).feet.x
        #expect(abs(a - splash.x) < 0.2 && abs(b - a) < 0.5, "\(splash.x) \(a) \(b)")
        let finish = try #require(LaunchDirector.finishTime(inp))
        for i in 0...Int((finish - 0.48) * 480) {
            let f = AssembleScene.frame(at: 0.48 + Double(i) / 480, inp)
            for o in fourAccounts { #expect(!Self.covers(f, o), "t \(0.48 + Double(i) / 480): over \(o)") }
        }
    }

    /// A hand-off in the middle of the splash's hop whose way from the air crosses words or rows (every arc from the air
    /// falls the same way, only its sideways timing changes): the creature finishes its hop and leaps from the landing on
    /// a clear way instead. The screens never wait for that leap: they come in from the hand-off when the rest of the hop is
    /// clear too, else as the hop lands. While they show, the creature is never over a word or a row.
    @Test func aHandOffInTheHopLandsFirstRatherThanKeepTheScreensWaiting() throws {
        for obstacles in [fourAccounts, fourAccountsAsABlock] {
            for i in 0...27 {
                let ready = 0.83 + Double(i) * 0.01
                let inp = LaunchInput(size: size, readyAt: ready, target: footer, obstacles: obstacles)
                let plan = try #require(LaunchDirector.handoff(inp))
                let screens = plan.screensStart
                #expect(screens <= max(ready + LaunchDirector.screensDelay, AssembleScene.hopLand) + 1e-9, "ready \(ready): screens from \(screens)")
                var t = plan.start
                while t < plan.finish {
                    let f = LaunchDirector.frame(at: t, inp, plan: plan)
                    if f.screensOpacity > 0, let o = obstacles.first(where: { Self.covers(f, $0) }) {
                        Issue.record("ready \(ready) t \(t): over \(o)")
                        break
                    }
                    t += 1.0 / 240
                }
            }
        }
        // In the window as it is, the rest of the hop is clear: the screens come in 0.04 s after the hand-off.
        for ready in [0.86, 0.95, 1.05] {
            let plan = try #require(LaunchDirector.handoff(LaunchInput(size: size, readyAt: ready, target: footer, obstacles: fourAccounts)))
            #expect(!plan.held && abs(plan.screensStart - (ready + LaunchDirector.screensDelay)) < 1e-9, "ready \(ready)")
        }
        // With the cards as one block the hop reaches into it: the creature lands first, the screens come in as it lands.
        let block = try #require(LaunchDirector.handoff(LaunchInput(size: size, readyAt: 0.95, target: footer, obstacles: fourAccountsAsABlock)))
        #expect(block.leapStart == AssembleScene.hopLand && abs(block.screensStart - AssembleScene.hopLand) < 1e-9)
    }

    /// A click during the gather: the screens come in with the leap, from 0.04 s before it takes off, never under the
    /// pixel cloud, which spreads over the cards while it gathers.
    @Test func aSkipDuringTheGatherBringsTheScreensInWithTheLeap() throws {
        for (ready, skip, crouch) in [(0.05, 0.1, 0.16), (0.02, 0.0, (0.58 - 0.02) / 3)] {
            let inp = LaunchInput(size: size, readyAt: ready, skippedAt: skip, target: footer, obstacles: fourAccountsAsABlock)
            let from = max(ready, skip) + crouch - LaunchDirector.screensDelay
            #expect(AssembleScene.frame(at: from - 1e-6, inp).screensOpacity == 0, "skip \(skip)")
            #expect(AssembleScene.frame(at: from + 0.05, inp).screensOpacity > 0, "skip \(skip)")
            #expect(AssembleScene.frame(at: from + LaunchDirector.screensFade + 1e-6, inp).screensOpacity == 1, "skip \(skip)")
            var t = max(ready, skip)
            while t < from + 0.4 {
                let f = AssembleScene.frame(at: t, inp)
                if f.screensOpacity > 0, let o = fourAccountsAsABlock.first(where: { Self.covers(f, $0) }) {
                    Issue.record("skip \(skip) t \(t): over \(o)")
                    break
                }
                t += 1.0 / 240
            }
        }
        // An ordinary crouch: the screens start 0.04 s into the hand-off, as always.
        #expect(AssembleScene.frame(at: 0.48 + 0.04 + 0.03, input(0.2)).screensOpacity > 0)
    }

    @Test func theGuideLeapGoesThroughEmptySpace() {
        // The All set creature stands beside "Open Brainmerge", low in the window: from there, clear of the main window's
        // words and rows all the way to the footer.
        let byTheButton = LaunchTarget(feet: CGPoint(x: 381, y: 571), unit: 3, asleep: false)
        let end = GuideExit.finishTime(from: byTheButton, to: footer, reduceMotion: false)
        for i in 0...Int(end * 480) {
            let f = GuideExit.frame(at: Double(i) / 480, from: byTheButton, to: footer, obstacles: busy, reduceMotion: false)
            for o in busy { #expect(!Self.covers(f, o), "tau \(Double(i) / 480): over \(o)") }
        }
        #expect(GuideExit.frame(at: end, from: byTheButton, to: footer, obstacles: busy, reduceMotion: false).feet == footer.feet)
    }

    // MARK: The end of the guided setup (audit M14)

    /// The All set creature (48 pt, 3 pt cells) in the middle of the guide.
    let allSet = LaunchTarget(feet: CGPoint(x: 480, y: 150), unit: 3, asleep: false)

    @Test func theGuideLeapsIntoTheSidebar() {
        for asleep in [false, true] {
            var target = sidebar
            target.asleep = asleep
            let start = GuideExit.frame(at: 0, from: allSet, to: target, reduceMotion: false)
            #expect(start.feet == allSet.feet && start.unit == 3 && start.handingOff && start.screensOpacity == 0)
            #expect(start.guideOpacity == 1 && start.shadowOpacity == 0 && start.wordmarkOpacity == 0)
            // The guide goes in 0.2 s; the screens come in on the leap's 0.04 to 0.34.
            #expect(GuideExit.frame(at: 0.2, from: allSet, to: target, reduceMotion: false).guideOpacity == 0)
            #expect(GuideExit.frame(at: 0.04, from: allSet, to: target, reduceMotion: false).screensOpacity == 0)
            #expect(GuideExit.frame(at: 0.34, from: allSet, to: target, reduceMotion: false).screensOpacity == 1)
            let end = GuideExit.finishTime(from: allSet, to: target, reduceMotion: false)
            #expect(abs(end - (asleep ? 1.44 : 1.08)) < 1e-9)
            let landed = GuideExit.frame(at: end, from: allSet, to: target, reduceMotion: false)
            #expect(landed.finished && landed.feet == target.feet && landed.unit == 2 && landed.pose == (asleep ? .asleep : .rest))
            var prev = start
            for i in 1...Int(end * 120) {
                let f = GuideExit.frame(at: Double(i) / 120, from: allSet, to: target, reduceMotion: false)
                #expect(Self.finite(f) && hypot(f.feet.x - prev.feet.x, f.feet.y - prev.feet.y) <= 20 && abs(f.unit - prev.unit) <= 0.25)
                prev = f
            }
        }
    }

    @Test func theGuideExitDissolvesWithReduceMotionOrWithoutASource() {
        // No creature to leap (Reduce Motion, or the All set creature scrolled out of the window): the screens simply come in.
        for (source, reduce) in [(allSet, true), (nil, false), (nil, true)] as [(LaunchTarget?, Bool)] {
            let end = GuideExit.finishTime(from: source, to: sidebar, reduceMotion: reduce)
            #expect(abs(end - (reduce ? 0.15 : 0.34)) < 1e-9)
            for i in 0...Int(end * 120) {
                let f = GuideExit.frame(at: Double(i) / 120, from: source, to: sidebar, reduceMotion: reduce)
                #expect(f.pose.opacity == 0 && f.handingOff && Self.finite(f))
                if reduce { #expect(f.screensScale == 1) }
            }
            #expect(GuideExit.frame(at: end, from: source, to: sidebar, reduceMotion: reduce).finished)
            #expect(GuideExit.frame(at: end, from: source, to: sidebar, reduceMotion: reduce).screensOpacity == 1)
            #expect(GuideExit.frame(at: end, from: source, to: sidebar, reduceMotion: reduce).guideOpacity == 0)
        }
        // Reduce Motion: a 0.15 s linear dissolve, nothing moves.
        #expect(abs(GuideExit.finishTime(from: allSet, to: sidebar, reduceMotion: true) - 0.15) < 1e-9)
        let half = GuideExit.frame(at: 0.075, from: allSet, to: sidebar, reduceMotion: true)
        #expect(abs(half.screensOpacity - 0.5) < 1e-9 && abs(half.guideOpacity - 0.5) < 1e-9 && half.screensScale == 1)
    }

    @Test func theGuideExitWithNoTargetHopsInPlace() {
        // The splash's hop at its own size: 2.4 cells of 3 pt, 0.30 s in the air, then the fade.
        let end = GuideExit.finishTime(from: allSet, to: nil, reduceMotion: false)
        #expect(abs(end - (0.08 + 0.30 + 0.2)) < 1e-9)
        let gone = GuideExit.frame(at: end, from: allSet, to: nil, reduceMotion: false)
        #expect(gone.finished && gone.pose.opacity == 0 && gone.feet == allSet.feet && gone.unit == allSet.unit)
        let highest = (0...240).map { GuideExit.frame(at: Double($0) / 240, from: allSet, to: nil, reduceMotion: false).feet.y }.min()!
        #expect(abs(highest - (allSet.feet.y - 2.4 * 3)) < 0.3)
    }
}
