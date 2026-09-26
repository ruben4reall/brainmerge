import SwiftUI

// The launch, "assemble, then leap home": the creature's own grid appears exploded and gathers into one, clicks together,
// opens its eyes and hops; once the app is ready it leaps into its place (the sidebar footer, or the welcome creature of
// the guided setup) while the window's screens fade in underneath. Every frame is a pure function of time: the views only
// draw frames, the tests check them.

/// Where a leap lands: the creature it becomes, in the window's coordinates.
public struct LaunchTarget: Equatable, Sendable {
    /// The middle of the bottom edge of the target's grid, on whole points.
    public var feet: CGPoint
    /// Its cell, in points (2 for the 32 pt sidebar creature, 4 for the welcome one).
    public var unit: CGFloat
    /// The sidebar creature sleeps while no account is open: the leap ends with it dozing off.
    public var asleep: Bool

    public init(feet: CGPoint, unit: CGFloat, asleep: Bool) { self.feet = feet; self.unit = unit; self.asleep = asleep }

    /// From a creature view's layout frame, which is exactly its grid (16 by 11 cells).
    public init(frame: CGRect, asleep: Bool) {
        let unit = frame.width / CGFloat(Creature.columns)
        self.init(feet: CGPoint(x: (frame.minX + CGFloat(Creature.columns / 2) * unit).rounded(),
                                y: (frame.minY + CGFloat(Creature.rows) * unit).rounded()), unit: unit, asleep: asleep)
    }
}

/// The splash's inputs, all on its own clock (seconds from its first frame): the window, when the app became ready, when
/// the person clicked or pressed a key, and where the creature lives in the window (nil: nowhere to go).
public struct LaunchInput: Sendable {
    public var size: CGSize
    public var readyAt: Double?
    public var skippedAt: Double?
    public var target: LaunchTarget?
    public var reduceMotion: Bool
    public init(size: CGSize, readyAt: Double?, skippedAt: Double? = nil, target: LaunchTarget? = nil, reduceMotion: Bool = false) {
        self.size = size; self.readyAt = readyAt; self.skippedAt = skippedAt; self.target = target; self.reduceMotion = reduceMotion
    }
}

/// What one frame shows. The screens and the guide read their opacity from the same frame: one clock, never two animations.
public struct LaunchFrame: Equatable, Sendable {
    public var pose = Creature.Pose()
    /// The creature's feet in the window and its cell (7 pt on the splash, the target's once landed).
    public var feet: CGPoint
    public var unit: CGFloat
    /// The flat `Colors.selection` row under the splash's feet, and the cells trimmed on each side.
    public var shadowOpacity = 0.0
    public var shadowInset: CGFloat = 0
    /// "Brainmerge" under the creature: it rises (points below its place) and sharpens (blur radius) as it comes in.
    public var wordmarkOpacity = 0.0
    public var wordmarkRise: CGFloat = 0
    public var wordmarkBlur: CGFloat = 0
    /// "Waking up…", on a slow launch only.
    public var captionOpacity = 0.0
    /// The window's screens, under the leaping creature.
    public var screensOpacity = 0.0
    public var screensScale: CGFloat = 1
    /// The guided setup, fading out under the leap that ends it.
    public var guideOpacity = 1.0
    /// The hand-off has started: the splash takes no more clicks, the screens take them.
    public var handingOff = false
    /// The overlay can go: the creature underneath is exactly this one.
    public var finished = false

    public init(feet: CGPoint, unit: CGFloat) { self.feet = feet; self.unit = unit }
}

// MARK: - The splash

/// The signature beat and the idle walk, before any hand-off.
public enum AssembleScene {
    public static let unit = Theme.Launch.unit
    /// The still for the README header, the site and store images: whole, at rest, eyes open, wordmark in.
    public static let heroTime = Theme.Launch.heroTime
    /// The earliest hand-off, in seconds (`Theme.Launch.minimumVisible`).
    public static let minimumVisible: Double = {
        let c = Theme.Launch.minimumVisible.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }()

    // The gather: the exploded ghost fades in where it stands, then its pixels spring home, inner ones first.
    static let fadeIn = 0.12, settleIn = 0.12
    static let gather = 0.04, staggerSpan = 0.14, staggerJitter = 0.04, spreadJitter = 0.25
    static let pixelSpring = Ease.Spring(response: 0.30, damping: 0.86)
    static let pixelSnap = 0.34
    /// Every pixel home.
    public static let assembled = 0.58
    // The click when the rim lands: a whole-body squash from the feet, settled by 0.70. The eyes appear then, asleep.
    static let clickAt = 0.44, clickVelocity = -1.1, clickSettled = 0.70
    static let click = Ease.Spring(response: 0.30, damping: 0.55)
    static let eyesOpen: [(Double, Double)] = [(0.54, 0.5), (0.60, 1)]
    static let shadowIn = 0.18, shadowOver = 0.30
    /// The wordmark rises after the earliest hand-off: a fast launch never flashes it.
    public static let wordmarkIn = 0.52, wordmarkDuration = 0.40
    // The hop for joy: crouch, 2.4 cells up, land.
    static let hopCrouch = 0.74, hopTakeoff = 0.82, hopLand = 1.12
    static let hopHeight: CGFloat = 2.4
    static let landSpring = Ease.Spring(response: 0.34, damping: 0.50)
    static let landSettled = 1.44
    static let blinkAt = 1.30
    /// The walk of a slow launch, one frame per 0.12 s from a passing frame.
    public static let idleStart = 1.52

    /// Where the creature's feet stand on the splash: its body's middle `lift` above the window's middle, on whole points
    /// (the cell is whole too, so every edge of the rest grid lands on a whole point).
    public static func splashFeet(in size: CGSize) -> CGPoint {
        CGPoint(x: (size.width / 2).rounded(.down), y: (size.height / 2 - Theme.Launch.lift + 38).rounded(.down))
    }

    /// The ground shadow: the legs' twelve columns, `inset` cells narrower on each side, on whole points.
    public static func shadowRect(feet: CGPoint, inset: CGFloat) -> CGRect {
        let half = (max(0.5, 6 - inset) * unit).rounded()
        return CGRect(x: feet.x - half, y: feet.y, width: 2 * half, height: unit)
    }

    // MARK: Pixels

    static let homes = Creature.bodyPixels()
    static let center = CGPoint(x: CGFloat(Creature.columns) / 2, y: CGFloat(Creature.rows) / 2)
    static let rimRadius: Double = homes.map { hypot(Double($0.x) + 0.5 - center.x, Double($0.y) + 0.5 - center.y) }.max() ?? 1

    /// The grid, exploded: every pixel starts on its own ray from the body's center, about 2.4 times as far, and springs
    /// home. The formation keeps the creature's order, so it reads as the creature coming together, not confetti.
    /// Nil once every pixel is home.
    public static func pixelStates(at t: Double) -> [PixelState]? {
        guard t < assembled else { return nil }
        let fade = Ease.out(Ease.progress(t, from: 0, over: fadeIn))
        return homes.map { p in
            let hx = Double(p.x) + 0.5 - center.x, hy = Double(p.y) + 0.5 - center.y
            let local = t - (gather + staggerSpan * hypot(hx, hy) / rimRadius + staggerJitter * Dice.hash01(p.x, p.y))
            if local >= pixelSnap { return PixelState() }
            let k = local <= 0 ? 0 : pixelSpring.value(local)
            let spread = Theme.Launch.gatherSpread + spreadJitter * Dice.hash01(p.x, p.y, 7)
            let m = (spread + (1 - spread) * k) * (1 + settleIn * (1 - fade))   // the ghost settles in as it fades in
            let dx = hx * (m - 1), dy = hy * (m - 1)
            if abs(dx) < 0.03 && abs(dy) < 0.03 && local > 0.2 { return PixelState() }
            return PixelState(dx: dx, dy: dy, scale: 1, opacity: fade)
        }
    }

    // MARK: The beat

    /// The creature and its shadow on the splash at `t`, with no hand-off.
    public static func beat(at t: Double, size: CGSize) -> LaunchFrame {
        let ground = splashFeet(in: size)
        var f = LaunchFrame(feet: ground, unit: unit)
        var pose = Creature.Pose()
        pose.pixels = pixelStates(at: t)
        let shadow = Ease.progress(t, from: shadowIn, over: shadowOver)
        f.shadowOpacity = shadow
        f.shadowInset = 6 * (1 - shadow)

        // Eyes: none on a cloud of pixels, the asleep dash from the click, then half, then open.
        if t < clickAt {
            pose.eyeHeight = 0
        } else if t < eyesOpen[0].0 {
            pose.eyeHeight = Creature.Pose.asleep.eyeHeight
            pose.eyeBottom = Creature.Pose.asleep.eyeBottom
        } else {
            pose.eyeHeight = CGFloat(Ease.steps(t, eyesOpen, before: 1))
        }

        if t >= clickAt && t < clickSettled {
            let d = CGFloat(click.displacement(t - clickAt, from: 0, velocity: clickVelocity)
                            * (1 - Ease.progress(t, from: clickSettled - 0.08, over: 0.08)))
            pose.scaleY = 1 + d
            pose.scaleX = 1 - 0.6 * d
        }

        if t >= hopCrouch && t < hopTakeoff {
            let k = CGFloat(Ease.out(Ease.progress(t, from: hopCrouch, over: hopTakeoff - hopCrouch)))
            pose.scaleY = 1 - 0.12 * k
            pose.scaleX = 1 + 0.07 * k
            pose.eyeHeight = 0.5
        } else if t >= hopTakeoff && t < hopLand {
            let u = (t - hopTakeoff) / (hopLand - hopTakeoff)
            let h = hopHeight * CGFloat(4 * u * (1 - u))
            f.feet.y = ground.y - h * unit
            let stretch = CGFloat(0.12 * max(0, 1 - u / 0.45) + 0.04 * max(0, (u - 0.7) / 0.3))
            pose.scaleY = 1 + stretch
            pose.scaleX = 1 - 0.6 * stretch
            pose.legsTucked = u > 0.08 && u < 0.92
            let arms: ArmPose = u > 0.05 && u < 0.9 ? .lift1 : .rest
            pose.armLeft = arms; pose.armRight = arms
            f.shadowInset = h * 0.9
            f.shadowOpacity = Double(1 - 0.35 * h / hopHeight)
        } else if t >= hopLand && t < idleStart {
            let d = CGFloat(landSpring.displacement(t - hopLand, from: -0.14) * (1 - Ease.progress(t, from: landSettled - 0.08, over: 0.08)))
            pose.scaleY = 1 + d
            pose.scaleX = 1 - 0.7 * d
            pose.eyeHeight = CGFloat(Ease.steps(t, Leap.blink(at: blinkAt), before: 1))
        } else if t >= idleStart {
            let index = walkIndex(at: t)
            pose = Creature.walkFrame(index)
            f.shadowInset = CGFloat(Creature.walkShadow(index).lowerBound - (Creature.legColumns.min() ?? 0))
        }
        f.pose = pose
        return f
    }

    /// Walk frame at `t` (a slow launch only): starts on a passing frame (1), then 2, 3, 0, looping.
    public static func walkIndex(at t: Double) -> Int {
        let k = Int(((t - idleStart) / LaunchDirector.walkFrame + 0.001).rounded(.down))
        return (1 + max(0, k)) % Creature.walkCycle
    }

    /// The launch at `t`: the beat, then the hand-off once the app is ready.
    public static func frame(at t: Double, _ input: LaunchInput) -> LaunchFrame { LaunchDirector.frame(at: t, input) }
}

// MARK: - The hand-off

public enum LaunchDirector {
    public static let walkFrame = Theme.Launch.frameDuration
    public static let captionAt = Theme.Launch.slowCaptionAfter, captionFade = 0.30
    /// The screens come in under the leap: from 0.04 s after the hand-off, over `Theme.Launch.fade`.
    public static let screensDelay = 0.04, screensFade = Theme.Launch.fade
    /// The splash's words go in 0.16 s, the shadow from half the crouch over 0.16 s.
    public static let textOut = 0.16, shadowAway = 0.16
    /// A skip during the gather finishes it this many times faster, inside the crouch (which lasts until it is whole).
    static let catchUp = 3.0
    /// With nowhere to land, the creature hops in place and fades out.
    static let fadeWithoutTarget = 0.2

    /// When the hand-off starts: never before ready; not before 0.48 s unless skipped; during the walk, on the next contact
    /// frame (the walk's contact is the crouch the leap winds up from). A late click never moves a hand-off already decided.
    public static func handoffStart(readyAt: Double?, skippedAt: Double?) -> Double? {
        guard let ready = readyAt else { return nil }
        let minimum = AssembleScene.minimumVisible
        let earliest = max(ready, min(skippedAt ?? minimum, minimum))
        guard earliest > AssembleScene.idleStart else { return earliest }
        var k = Int(((earliest - AssembleScene.idleStart) / walkFrame - 0.001).rounded(.up))
        while (1 + k) % 2 != 0 { k += 1 }
        return AssembleScene.idleStart + Double(k) * walkFrame
    }

    /// The splash at `t` with its words: the beat, the wordmark rising, "Waking up…" on a slow launch.
    static func splash(at t: Double, size: CGSize) -> LaunchFrame {
        var f = AssembleScene.beat(at: t, size: size)
        let w = Ease.out(Ease.progress(t, from: AssembleScene.wordmarkIn, over: AssembleScene.wordmarkDuration))
        f.wordmarkOpacity = w
        f.wordmarkRise = CGFloat(8 * (1 - w))
        f.wordmarkBlur = CGFloat(1.5 * (1 - w))
        f.captionOpacity = Ease.out(Ease.progress(t, from: captionAt, over: captionFade))
        return f
    }

    /// How a hand-off plays. The screens come in from `start`; the creature leaps from `leapStart`: the hand-off itself, or,
    /// when it is mid-hop and no natural arc starts from there (a higher target, the hop's own fall), the hop's landing,
    /// whose squash is its crouch. It never kicks up again in the air.
    struct Handoff {
        let start: Double
        let leapStart: Double
        /// Nil when there is nowhere to go and the creature is already hopping: that hop is its hop in place.
        let leap: Leap?
        /// With nowhere to go: when it starts fading out (its touchdown).
        let fadeFrom: Double?
        var finish: Double { fadeFrom.map { $0 + fadeWithoutTarget } ?? leapStart + (leap?.end ?? 0) }
    }

    static func handoff(_ input: LaunchInput) -> Handoff? {
        guard let hs = handoffStart(readyAt: input.readyAt, skippedAt: input.skippedAt) else { return nil }
        let airborne = hs >= AssembleScene.hopTakeoff && hs < AssembleScene.hopLand
        if airborne {
            if let target = input.target {
                let fromTheAir = leap(input, from: hs, to: target)
                if fromTheAir.keepsItsSpeed { return Handoff(start: hs, leapStart: hs, leap: fromTheAir, fadeFrom: nil) }
                let land = AssembleScene.hopLand
                return Handoff(start: hs, leapStart: land, leap: leap(input, from: land, to: target, landed: true), fadeFrom: nil)
            }
            return Handoff(start: hs, leapStart: hs, leap: nil, fadeFrom: AssembleScene.hopLand)
        }
        // A skip during the gather: it runs 3 times faster from the hand-off, and the crouch holds until it is whole.
        let crouch = max(Leap.anticipation, (AssembleScene.assembled - hs) / catchUp)
        guard let target = input.target else {
            let hop = Leap.hopInPlace(from: leap(input, from: hs, to: nil).start, feet: AssembleScene.splashFeet(in: input.size),
                                      unit: AssembleScene.unit, crouch: crouch)
            return Handoff(start: hs, leapStart: hs, leap: hop, fadeFrom: hs + hop.touchdown)
        }
        return Handoff(start: hs, leapStart: hs, leap: leap(input, from: hs, to: target, crouch: crouch), fadeFrom: nil)
    }

    /// The leap from the splash's pose at `t` (and its vertical speed: it may be mid-hop, unless it just `landed`) to the
    /// target, or back to the ground where it stands when there is none.
    static func leap(_ input: LaunchInput, from t: Double, to target: LaunchTarget?, crouch: Double = Leap.anticipation,
                     landed: Bool = false) -> Leap {
        let start = AssembleScene.beat(at: t, size: input.size)
        let before = AssembleScene.beat(at: t - 1.0 / 240, size: input.size)
        var pose = start.pose
        pose.pixels = nil
        let ground = LaunchTarget(feet: AssembleScene.splashFeet(in: input.size), unit: AssembleScene.unit, asleep: false)
        return Leap(start: pose, feet: start.feet, unit: start.unit, startVelocityY: landed ? 0 : (start.feet.y - before.feet.y) * 240,
                    target: target ?? ground, crouch: crouch)
    }

    public static func frame(at t: Double, _ input: LaunchInput) -> LaunchFrame {
        if input.reduceMotion { return reducedFrame(at: t, input) }
        guard let plan = handoff(input), t >= plan.start else { return splash(at: t, size: input.size) }
        let hs = plan.start, tau = t - hs
        var f: LaunchFrame
        if let leap = plan.leap, t >= plan.leapStart {
            let (pose, feet, unit) = leap.frame(at: t - plan.leapStart)
            f = LaunchFrame(feet: feet, unit: unit)
            f.pose = pose
            // The shadow thins out and goes as the creature lifts off.
            let base = AssembleScene.beat(at: plan.leapStart, size: input.size)
            let away = Ease.out(Ease.progress(t - plan.leapStart, from: leap.takeoff / 2, over: shadowAway))
            f.shadowOpacity = base.shadowOpacity * (1 - away)
            f.shadowInset = base.shadowInset + 3 * CGFloat(away)
        } else {
            // Finishing the hop it was in, its shadow under it.
            f = AssembleScene.beat(at: t, size: input.size)
        }
        f.pose.pixels = AssembleScene.pixelStates(at: hs + tau * catchUp)
        if hs + tau * catchUp < AssembleScene.clickAt {   // no eyes on a cloud of pixels: they come with the click, as in the beat
            f.pose.eyeHeight = 0
            f.pose.eyeBottom = Creature.Pose.rest.eyeBottom
        }
        f.handingOff = true

        // The words go at once, from wherever they were.
        let before = splash(at: hs, size: input.size)
        let out = Ease.out(Ease.progress(tau, from: 0, over: textOut))
        f.wordmarkOpacity = before.wordmarkOpacity * (1 - out)
        f.wordmarkRise = before.wordmarkRise
        f.wordmarkBlur = before.wordmarkBlur
        f.captionOpacity = before.captionOpacity * (1 - out)
        screens(&f, tau: tau)

        if let fade = plan.fadeFrom { f.pose.opacity = 1 - Ease.out(Ease.progress(t, from: fade, over: fadeWithoutTarget)) }
        f.finished = t >= plan.finish
        if f.finished { f.screensOpacity = 1; f.screensScale = 1 }
        return f
    }

    /// The window's content under the leap: opacity 0 to 1 and scale 0.985 to 1, from 0.04 s over 0.30 s.
    static func screens(_ f: inout LaunchFrame, tau: Double) {
        let s = Ease.out(Ease.progress(tau, from: screensDelay, over: screensFade))
        f.screensOpacity = s
        f.screensScale = CGFloat(1 - 0.015 * (1 - s))
    }

    /// When the overlay goes, on the splash's clock; nil until the app is ready.
    public static func finishTime(_ input: LaunchInput) -> Double? {
        if input.reduceMotion { return input.readyAt.map { max($0, AssembleScene.minimumVisible) + Theme.Launch.reducedFade } }
        return handoff(input)?.finish
    }

    /// Reduce Motion: the creature is simply there (a 0.15 s fade in), still, eyes open, with its shadow and the wordmark;
    /// no gather, no hop, no walk, no leap. "Waking up…" fades in at 2 s. Once ready, and at least 0.48 s in, a 0.15 s
    /// linear dissolve: the splash out, the window in, the sidebar creature already in its place.
    public static func reducedFrame(at t: Double, _ input: LaunchInput) -> LaunchFrame {
        let fade = Theme.Launch.reducedFade
        var f = LaunchFrame(feet: AssembleScene.splashFeet(in: input.size), unit: AssembleScene.unit)
        let appear = Ease.progress(t, from: 0, over: fade)
        f.pose.opacity = appear
        f.shadowOpacity = appear
        f.wordmarkOpacity = appear
        f.captionOpacity = Ease.progress(t, from: captionAt, over: fade)
        guard let ready = input.readyAt else { return f }
        let hs = max(ready, AssembleScene.minimumVisible)
        guard t >= hs else { return f }
        f.handingOff = true
        f.finished = t >= hs + fade
        let k = f.finished ? 1 : Ease.progress(t, from: hs, over: fade)
        f.pose.opacity = 1 - k
        f.shadowOpacity = 1 - k
        f.wordmarkOpacity = 1 - k
        f.captionOpacity *= 1 - k
        f.screensOpacity = k
        return f
    }
}

// MARK: - The leap

/// From whatever pose it is in, the creature crouches, leaps along a ballistic arc to its home, shrinking to the target's
/// cell, lands with a squash, looks back at you, blinks, and takes the target's state. Pure: a function of the time since
/// the hand-off. The launch and the end of the guided setup use the same leap.
public struct Leap: Sendable {
    public static let anticipation = Theme.Launch.anticipation
    public static let flight = Theme.Launch.leap
    /// The apex, above the higher of the start and the target.
    public static let apex = Theme.Launch.leapApex
    static let landing = Ease.Spring(response: 0.30, damping: 0.50)
    static let squash = 0.20
    /// After touchdown: the squash is exactly rest once its ringing stays under 0.004.
    static let settled = landing.settleTime(from: -squash, within: 0.004)
    static let lookBack = 0.18, blinkAt = 0.30, dozeAt = 0.62, dozeDash = 0.16

    public let start: Creature.Pose
    public let feet: CGPoint
    public let unit: CGFloat
    /// Points per second, negative is up (the splash may be mid-hop).
    public let startVelocityY: CGFloat
    public let target: LaunchTarget
    /// The crouch before it (from the ground): 0.08 s, longer while a skipped gather finishes.
    public let crouch: Double
    /// Takeoff to touchdown, and the apex above the higher end: the leap's 0.50 s and 12 pt, or the splash hop's own.
    public let flightTime: Double
    public let apexHeight: CGFloat

    public init(start: Creature.Pose, feet: CGPoint, unit: CGFloat, startVelocityY: CGFloat, target: LaunchTarget,
                crouch: Double = Leap.anticipation, flight: Double = Leap.flight, apex: CGFloat = Leap.apex) {
        self.start = start; self.feet = feet; self.unit = unit; self.startVelocityY = startVelocityY; self.target = target
        self.crouch = max(crouch, Self.anticipation); self.flightTime = flight; self.apexHeight = apex
    }

    /// Nowhere to go: the splash's own hop where it stands (2.4 cells, 0.30 s in the air), so the same gravity, never a
    /// slow float.
    public static func hopInPlace(from start: Creature.Pose, feet: CGPoint, unit: CGFloat, crouch: Double = Leap.anticipation) -> Leap {
        Leap(start: start, feet: feet, unit: unit, startVelocityY: 0, target: LaunchTarget(feet: feet, unit: unit, asleep: false),
             crouch: crouch, flight: AssembleScene.hopLand - AssembleScene.hopTakeoff, apex: AssembleScene.hopHeight * unit)
    }

    /// On the ground: still, legs down. In the air (mid-hop) the crouch is skipped.
    var grounded: Bool { abs(startVelocityY) < 1 && !start.legsTucked }
    public var takeoff: Double { grounded ? crouch : 0 }
    public var touchdown: Double { takeoff + flightTime }
    public var end: Double { touchdown + (target.asleep ? 0.86 : 0.50) }
    /// Toward the target: -1 left, 1 right, 0 straight up (a hop in place).
    var direction: Int { abs(target.feet.x - feet.x) < 1 ? 0 : target.feet.x < feet.x ? -1 : 1 }

    /// The arc's initial vertical speed and gravity (pt/s, pt/s²), landing on the target after `flight`. From the ground the
    /// apex is `apex` above the higher end: H = apex + max(0, start - target), s = (√(2H) + √(2H + 2D)) / T, g = s²,
    /// vy = -√(2gH); the root is never negative. From the air the arc keeps the speed it had (`keepsItsSpeed`); when that
    /// would need less than half the ground arc's gravity, the launch does not leap from the air (it lands first).
    public var ballistics: (vy: CGFloat, g: CGFloat) {
        let arc = groundArc
        guard !grounded else { return arc }
        let kept = keptArc
        return kept.g >= arc.g / 2 ? kept : arc
    }
    /// From the ground: the arc with its apex `apex` above the higher end.
    var groundArc: (vy: CGFloat, g: CGFloat) {
        let T = CGFloat(flightTime), D = target.feet.y - feet.y
        let H = apexHeight + max(0, -D)
        let s = ((2 * H).squareRoot() + (2 * H + 2 * D).squareRoot()) / T
        return (vy: -s * (2 * H).squareRoot(), g: s * s)
    }
    /// From the air: the arc that keeps the speed the creature has.
    var keptArc: (vy: CGFloat, g: CGFloat) {
        let T = CGFloat(flightTime), D = target.feet.y - feet.y
        return (startVelocityY, 2 * (D - startVelocityY * T) / (T * T))
    }
    /// From the air, the speed it has carries it to the target under a natural gravity (at least half the ground arc's).
    public var keepsItsSpeed: Bool { !grounded && keptArc.g >= groundArc.g / 2 }

    /// The blink after a landing: half, slit, half, open.
    static func blink(at start: Double) -> [(Double, Double)] {
        [(start, 0.5), (start + 0.04, 0.15), (start + 0.10, 0.5), (start + 0.14, 1)]
    }

    public func frame(at tau: Double) -> (pose: Creature.Pose, feet: CGPoint, unit: CGFloat) {
        var pose = start
        pose.pixels = nil
        if tau < takeoff {
            // Anticipation: a quick crouch from the current pose, eyes squeezed.
            let k = CGFloat(Ease.out(Ease.progress(tau, from: 0, over: Self.anticipation)))
            pose.scaleY = start.scaleY + (0.86 - start.scaleY) * k
            pose.scaleX = start.scaleX + (1.08 - start.scaleX) * k
            if tau > 0.03 { pose.eyeHeight = 0.5; pose.eyeBottom = Creature.Pose.rest.eyeBottom }
            return (pose, feet, unit)
        }
        pose.raise = 0
        pose.breath = 0
        pose.offset = .zero
        pose.liftedLegs = Creature.Pose.rest.liftedLegs
        pose.eyeBottom = Creature.Pose.rest.eyeBottom
        if tau < touchdown {
            let u = (tau - takeoff) / flightTime, tf = CGFloat(tau - takeoff)
            let (vy, g) = ballistics
            let at = CGPoint(x: feet.x + (target.feet.x - feet.x) * CGFloat(Ease.travel(u)), y: feet.y + vy * tf + g * tf * tf / 2)
            let cell = unit + (target.unit - unit) * CGFloat(Ease.shrink(u))
            // Stretch along the motion: strong at takeoff, gone at the apex, a little again on the way down.
            let stretch = CGFloat(0.14 * max(0, 1 - u / 0.3) + 0.05 * max(0, (u - 0.7) / 0.3))
            var scaleY = 1 + stretch, scaleX = 1 - 0.6 * stretch
            if !grounded {
                // From the air: the body blends from the hop's squash and stretch over 0.12 s, no snap.
                let q = Ease.progress(tau, from: 0, over: 0.12), p = CGFloat(q * q * (3 - 2 * q))
                scaleY = start.scaleY + (scaleY - start.scaleY) * p
                scaleX = start.scaleX + (scaleX - start.scaleX) * p
            }
            pose.scaleY = scaleY
            pose.scaleX = scaleX
            pose.rotation = 5 * sin(.pi * u) * Double(direction)
            pose.legsTucked = u < 0.94 && (u > 0.03 || !grounded)
            let arms: ArmPose = u < 0.86 && (u > 0.03 || !grounded) ? .lift1 : .rest
            pose.armLeft = arms; pose.armRight = arms
            pose.eyeHeight = 1
            pose.look = u > 0.08 ? direction : 0
            return (pose, at, cell)
        }
        // Touchdown: a squash, then a bouncy settle; exactly the rest grid once settled.
        let tl = tau - touchdown
        let d = CGFloat(Self.landing.displacement(tl, from: -Self.squash))
        let settled = tl >= Self.settled
        pose.scaleY = settled ? 1 : 1 + d
        pose.scaleX = settled ? 1 : 1 - 0.7 * d
        pose.rotation = 0
        pose.legsTucked = false
        pose.armLeft = .rest; pose.armRight = .rest
        pose.look = tl < Self.lookBack ? direction : 0
        pose.eyeHeight = CGFloat(Ease.steps(tl, Self.blink(at: Self.blinkAt), before: 1))
        if target.asleep && tl >= Self.dozeAt {
            pose.eyeHeight = 0.5
            if tl >= Self.dozeAt + Self.dozeDash { pose = Creature.Pose.asleep.with(scaleX: pose.scaleX, scaleY: pose.scaleY) }
        }
        return (pose, target.feet, target.unit)
    }
}

private extension Creature.Pose {
    func with(scaleX: CGFloat, scaleY: CGFloat) -> Creature.Pose {
        var pose = self
        pose.scaleX = scaleX; pose.scaleY = scaleY
        return pose
    }
}

// MARK: - The end of the guided setup

/// "Open Brainmerge" (audit M14): the All set creature leaps into the sidebar footer with the launch's leap, the guide fades
/// out in 0.2 s, the screens fade in on the leap's 0.04 to 0.34 s. With Reduce Motion, a 0.15 s dissolve; with no creature
/// to leap from (scrolled out of the window), the screens simply come in.
public enum GuideExit {
    static let guideFade = 0.2

    public static func frame(at tau: Double, from source: LaunchTarget?, to target: LaunchTarget?, reduceMotion: Bool) -> LaunchFrame {
        guard let source, !reduceMotion else { return dissolve(at: tau, reduceMotion: reduceMotion) }
        let leap = leap(from: source, to: target)
        let (pose, feet, unit) = leap.frame(at: tau)
        var f = LaunchFrame(feet: feet, unit: unit)
        f.pose = pose
        f.handingOff = true
        f.guideOpacity = 1 - Ease.out(Ease.progress(tau, from: 0, over: guideFade))
        LaunchDirector.screens(&f, tau: tau)
        if target == nil {
            f.pose.opacity = 1 - Ease.out(Ease.progress(tau, from: leap.touchdown, over: LaunchDirector.fadeWithoutTarget))
        }
        f.finished = tau >= finishTime(from: source, to: target, reduceMotion: false)
        if f.finished { f.screensOpacity = 1; f.screensScale = 1; f.guideOpacity = 0 }
        return f
    }

    static func dissolve(at tau: Double, reduceMotion: Bool) -> LaunchFrame {
        var f = LaunchFrame(feet: .zero, unit: 1)
        f.pose.opacity = 0
        f.handingOff = true
        if reduceMotion {
            let k = Ease.progress(tau, from: 0, over: Theme.Launch.reducedFade)
            f.screensOpacity = k
            f.guideOpacity = 1 - k
        } else {
            LaunchDirector.screens(&f, tau: tau)
            f.guideOpacity = 1 - Ease.out(Ease.progress(tau, from: 0, over: guideFade))
        }
        f.finished = tau >= finishTime(from: nil, to: nil, reduceMotion: reduceMotion)
        if f.finished { f.screensOpacity = 1; f.screensScale = 1; f.guideOpacity = 0 }
        return f
    }

    /// When the overlay goes, from the click on "Open Brainmerge".
    public static func finishTime(from source: LaunchTarget?, to target: LaunchTarget?, reduceMotion: Bool) -> Double {
        if reduceMotion { return Theme.Launch.reducedFade }
        guard let source else { return LaunchDirector.screensDelay + LaunchDirector.screensFade }
        let leap = leap(from: source, to: target)
        return target == nil ? leap.touchdown + LaunchDirector.fadeWithoutTarget : leap.end
    }

    /// The All set creature's leap into the sidebar, or, with nowhere to go, the splash's hop where it stands.
    static func leap(from source: LaunchTarget, to target: LaunchTarget?) -> Leap {
        guard let target else { return Leap.hopInPlace(from: .rest, feet: source.feet, unit: source.unit) }
        return Leap(start: .rest, feet: source.feet, unit: source.unit, startVelocityY: 0, target: target)
    }
}
