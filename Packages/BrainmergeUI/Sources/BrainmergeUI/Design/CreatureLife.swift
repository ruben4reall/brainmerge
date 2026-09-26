import SwiftUI

/// Things that happen to the creature. The app stamps each with the moment it was seen.
public enum CreatureEvent: Equatable, Sendable {
    case wake, doze, memorySaved, accountOpened, error
    /// Every reaction is short (under 0.8 s) and ends exactly at the rest pose.
    public var duration: Double {
        switch self {
        case .wake: return 0.46
        case .doze: return 0.70
        case .memorySaved: return 0.74
        case .accountOpened: return 0.62
        case .error: return 0.72
        }
    }
}

/// An event at a time on the view's clock, in seconds.
public struct CreatureStamp: Equatable, Sendable {
    public var event: CreatureEvent
    public var at: Double
    public init(_ event: CreatureEvent, at: Double) { self.event = event; self.at = at }
}

/// An event at a moment in time, as the app model stamps it; the view turns it into a `CreatureStamp` on its own clock.
public struct CreatureMoment: Equatable, Sendable {
    public var event: CreatureEvent
    public var date: Date
    public init(_ event: CreatureEvent, date: Date) { self.event = event; self.date = date }
}

/// A walk on the view's clock (an account is opening): from `start`, until `end` once the opening is over. It never stops
/// mid-step: it runs on to its next contact frame (`stop`), at most 0.24 s after `end`.
public struct CreatureWalk: Equatable, Sendable {
    public var start: Double
    public var end: Double?
    public init(start: Double, end: Double? = nil) { self.start = start; self.end = end }

    public static let frameDuration = Theme.Launch.frameDuration
    /// The walk's frame at `t`: the passing frame 1 first, so a click shows at once.
    public func index(at t: Double) -> Int { 1 + Int(((t - start) / Self.frameDuration + 1e-9).rounded(.down)) }
    /// The first contact frame at or after `end`.
    public var stop: Double? {
        guard let end else { return nil }
        var k = max(0, ((end - start) / Self.frameDuration - 1e-9).rounded(.up))
        if Int(k) % 2 == 0 { k += 1 }
        return start + k * Self.frameDuration
    }
    public func isActive(at t: Double) -> Bool { t >= start && t < (stop ?? .infinity) }
}

/// How much idle life a place gets. The sidebar is peripheral and always visible: blinks and rare glances only, and a
/// breath only while asleep. A stage (welcome, All set) breathes while awake too.
public struct LifeProfile: Equatable, Sendable {
    public var blinkEvery: ClosedRange<Double>
    public var glanceEvery: ClosedRange<Double>
    /// Device pixels.
    public var awakeBreath: Int
    public var sleepBreath: Int
    /// Grid cells.
    public var hopHeight: Double
    public static let companion = LifeProfile(blinkEvery: 3.4...7.5, glanceEvery: 9...16, awakeBreath: 0, sleepBreath: 1, hopHeight: 1.75)
    public static let stage = LifeProfile(blinkEvery: 2.6...6.0, glanceEvery: 5.5...10, awakeBreath: 2, sleepBreath: 2, hopHeight: 2.25)
}

public struct LifeFrame: Equatable, Sendable {
    public var pose = Creature.Pose()
    public var sprites: [Creature.Sprite] = []
    public init(pose: Creature.Pose = Creature.Pose(), sprites: [Creature.Sprite] = []) { self.pose = pose; self.sprites = sprites }
}

/// The creature's life: a pure function of the state, the time on the view's clock and the stamped events. Same inputs,
/// same frame: the view only draws frames, and tests check any moment.
///
/// Pixel-honest: at rest it is exactly the grid; eyes, arms, legs and breath change in whole cells or whole device pixels.
/// Smooth squash and stretch exists only inside reactions of 0.8 s or less that end on the rest pose.
public enum CreatureLife {
    // MARK: Sprites, on half cells

    static let sparkleFrames: [[String]] = [
        ["X"],
        [".X.", "XXX", ".X."],
        ["..X..", "..X..", "XX.XX", "..X..", "..X.."],
    ]
    static let zee = ["XXXX", "..X.", ".X..", "XXXX"]
    static let bang = ["XX", "XX", "XX", "XX", "..", "XX"]
    static var cream: Color { Theme.Colors.text }
    static var light: Color { Theme.Colors.accentLight }

    /// One sparkle's life: dot, cross, star, cross, dot (16%, 20%, 28%, 20%, 16%).
    static func sparkle(life f: Double) -> [String] {
        switch f {
        case ..<0.16: return sparkleFrames[0]
        case ..<0.36: return sparkleFrames[1]
        case ..<0.64: return sparkleFrames[2]
        case ..<0.84: return sparkleFrames[1]
        default: return sparkleFrames[0]
        }
    }

    // MARK: The idle schedule

    static let blinkCount = 14, glanceCount = 9
    static let firstBlink = 1.3, firstGlance = 3.1
    static let blinkLength = 0.14, doubleBlinkGap = 0.24, blinkApart = 1.0
    /// Stepped boundaries count as reached a hair early: `start + 0.14 - start` is not exactly 0.14 in floating point, and
    /// `nextChange` must find the pose already changed at the time it returns.
    static let epsilon = 1e-9

    /// A fixed phrase of intervals: irregular to the eye, identical on every run. After the phrase it repeats from its first
    /// start, every `loop` seconds.
    struct Phrase {
        var starts: [Double]
        var loop: Double
        init(seed: UInt64, stream: UInt64, count: Int, range: ClosedRange<Double>, first: Double) {
            var t = first
            starts = []
            for k in 0..<count {
                starts.append(t)
                t += Ease.lerp(range.lowerBound, range.upperBound, Dice.unit(seed, UInt64(k), stream))
            }
            loop = t - first
        }
        /// Every (index in the phrase, time) in [a, b], in order.
        func occurrences(from a: Double, to b: Double) -> [(index: Int, at: Double)] {
            guard b >= a, let first = starts.first, loop > 0 else { return [] }
            var out: [(Int, Double)] = []
            var n = max(0, Int(((a - first) / loop).rounded(.down)) - 1)
            while true {
                let base = Double(n) * loop
                if first + base > b { break }
                for (k, s) in starts.enumerated() where s + base >= a && s + base <= b { out.append((k, s + base)) }
                n += 1
            }
            return out
        }
    }

    struct Glance { var start: Double; var side: Int; var double: Bool; var hold: Double; var returnBlink: Bool
        var end: Double { double ? 1.3 : hold }
        func look(at t: Double) -> Int? {
            let d = t - start + CreatureLife.epsilon
            guard d >= 0, d < end else { return nil }
            return double && d >= 0.6 ? -side : side
        }
    }

    static func glances(from a: Double, to b: Double, profile: LifeProfile, seed: UInt64) -> [Glance] {
        let phrase = Phrase(seed: seed, stream: 3, count: glanceCount, range: profile.glanceEvery, first: firstGlance)
        return phrase.occurrences(from: a, to: b).map { i, start in
            let k = UInt64(i)
            return Glance(start: start, side: Dice.unit(seed, k, 5) < 0.5 ? -1 : 1, double: Dice.unit(seed, k, 6) < 0.3,
                          hold: Ease.lerp(0.7, 1.4, Dice.unit(seed, k, 4)), returnBlink: Dice.unit(seed, k, 7) < 0.55)
        }
    }

    /// The blinks that play in [a, b]: the phrase's blinks (one in five doubled, the partner 0.24 s later), and a blink 40 ms
    /// before the eyes come back from most glances. A blink within 1 s of the last one kept is skipped, and its partner with it.
    static func blinks(from a: Double, to b: Double, profile: LifeProfile, seed: UInt64) -> [Double] {
        // Start early enough that every decision before `a` is the same whatever the window: the refractory chain is short.
        let lead = 8.0
        let phrase = Phrase(seed: seed, stream: 1, count: blinkCount, range: profile.blinkEvery, first: firstBlink)
        var candidates: [(at: Double, partnerOf: Double?)] = []
        for (k, at) in phrase.occurrences(from: a - lead, to: b) {
            candidates.append((at, nil))
            if Dice.unit(seed, UInt64(k), 2) < 0.2 { candidates.append((at + doubleBlinkGap, at)) }
        }
        for g in glances(from: a - lead - 2, to: b, profile: profile, seed: seed) where g.returnBlink {
            candidates.append((g.start + g.end - 0.04, nil))
        }
        candidates.sort { $0.at < $1.at }
        var kept: [Double] = [], lastKept = -Double.infinity
        for c in candidates where c.at <= b {
            if let primary = c.partnerOf {
                // A partner plays only with its blink, and the next blink keeps 1 s from it too.
                if kept.contains(where: { abs($0 - primary) < 1e-9 }) { kept.append(c.at); lastKept = c.at }
            } else if c.at - lastKept >= blinkApart {
                kept.append(c.at); lastKept = c.at
            }
        }
        return kept.filter { $0 >= a - blinkLength }
    }

    /// Eye height of a blink started `d` seconds ago (stepped, never interpolated), or nil when not blinking.
    static func blink(_ d: Double) -> CGFloat? {
        switch d + epsilon {
        case 0..<0.04: return 0.5
        case 0.04..<0.10: return 0.2
        case 0.10..<blinkLength: return 0.5
        default: return nil
        }
    }

    static func idleEyes(t: Double, profile: LifeProfile, seed: UInt64) -> (height: CGFloat, look: Int) {
        var height: CGFloat = 1
        for start in blinks(from: t - blinkLength, to: t, profile: profile, seed: seed) { if let h = blink(t - start) { height = h } }
        let look = glances(from: t - 1.5, to: t, profile: profile, seed: seed).compactMap { $0.look(at: t) }.last ?? 0
        return (height, look)
    }

    /// Breathing as whole device pixels: 0 up to `amp` and back, the inhale (42%) shorter than the exhale. 0 at the start.
    static func breath(_ s: Double, period: Double, amp: Int) -> Int {
        guard amp > 0, s >= 0 else { return 0 }
        let f = (s / period).truncatingRemainder(dividingBy: 1)
        let v = f < 0.42 ? Ease.breath(f / 0.42) : 1 - Ease.breath((f - 0.42) / 0.58)
        return Int((v * Double(amp)).rounded())
    }
    static let awakePeriod = 3.6, sleepPeriod = 4.8
    /// The sleep loop (breath and Z) runs for the first minute asleep, in whole breaths, then the creature holds still.
    static let sleepLoop = 60.0
    static var sleepLoopEnd: Double { (sleepLoop / sleepPeriod).rounded(.down) * sleepPeriod }

    // MARK: The frame

    public static func frame(state: CreatureState, t: Double, events: [CreatureStamp] = [], profile: LifeProfile = .companion,
                             seed: UInt64 = 7, walking: CreatureWalk? = nil, asleepSince: Double? = nil,
                             reduceMotion: Bool = false) -> LifeFrame {
        if reduceMotion { return reducedFrame(state: state, t: t, events: events) }
        let stamps = effective(events, walking: walking)
        let base = idle(state: state, t: t, stamps: stamps, profile: profile, seed: seed, asleepSince: asleepSince)
        guard let active = stamps.last(where: { t >= $0.at && t < $0.at + $0.event.duration }) else {
            guard let walking, walking.isActive(at: t) else { return base }
            var f = base
            let walk = Creature.walkFrame(walking.index(at: t))
            f.pose.raise = walk.raise
            f.pose.liftedLegs = walk.liftedLegs
            f.pose.armLeft = walk.armLeft
            f.pose.armRight = walk.armRight
            f.pose.breath = 0
            return f
        }
        var r = react(active.event, tau: t - active.at, base: base, profile: profile)
        // Interrupted: the body blends from where the previous reaction left it, over 120 ms (smoothstep, no velocity kick).
        // Stepped fields (eyes, arms, legs) switch at once, as sprite frames do.
        if let previous = stamps.last(where: { $0.at < active.at && active.at < $0.at + $0.event.duration }) {
            let from = react(previous.event, tau: active.at - previous.at, base: base, profile: profile).pose
            let q = Ease.progress(t - active.at, from: 0, over: 0.12), p = q * q * (3 - 2 * q)
            r.pose.offset = CGVector(dx: Ease.lerp(from.offset.dx, r.pose.offset.dx, p), dy: Ease.lerp(from.offset.dy, r.pose.offset.dy, p))
            r.pose.scaleX = Ease.lerp(from.scaleX, r.pose.scaleX, p)
            r.pose.scaleY = Ease.lerp(from.scaleY, r.pose.scaleY, p)
        }
        return r
    }

    /// The stamps in order, an opened account's wave waiting for the walk's last step.
    static func effective(_ events: [CreatureStamp], walking: CreatureWalk?) -> [CreatureStamp] {
        events.map { stamp in
            guard stamp.event == .accountOpened, let walking, let stop = walking.stop, stamp.at >= walking.start, stamp.at < stop else { return stamp }
            return CreatureStamp(stamp.event, at: stop)
        }
        .sorted { $0.at < $1.at }
    }

    /// The idle life of a state, without reactions or the walk.
    static func idle(state: CreatureState, t: Double, stamps: [CreatureStamp], profile: LifeProfile, seed: UInt64, asleepSince: Double?) -> LifeFrame {
        var f = LifeFrame()
        switch state {
        case .asleep:
            f.pose = .asleep
            let s = t - (asleepSince ?? 0)
            if s >= 0, s < sleepLoopEnd {
                // A hair early, like the blinks: the step `nextChange` finds is then already drawn at the time it returns.
                f.pose.breath = breath(s + epsilon, period: sleepPeriod, amp: profile.sleepBreath)
                f.sprites += sleepZ(s)
            }
        case .awake, .glowing:
            let eyes = idleEyes(t: t, profile: profile, seed: seed)
            f.pose.eyeHeight = eyes.height
            f.pose.look = eyes.look
            f.pose.breath = breath(t, period: awakePeriod, amp: profile.awakeBreath)
            if state == .glowing, !stamps.contains(where: { $0.event == .memorySaved && t >= $0.at && t < $0.at + $0.event.duration }) {
                f.sprites += glowTwinkle(t - glowOrigin(t: t, stamps: stamps))
            }
        }
        return f
    }

    /// The Z's age in its breath: born 2.0 s into it, alive for 2.6 s. Negative or past 2.6 when there is none.
    static let zBorn = 2.0, zLife = 2.6
    static func zAge(_ s: Double) -> Double { (s + epsilon).truncatingRemainder(dividingBy: sleepPeriod) - zBorn }
    static func zFloats(_ s: Double) -> Bool { let age = zAge(s); return age >= 0 && age < zLife }

    /// The twinkles take over where the hop's sparkles end: their clock starts when the last hop landed (0 without one).
    static func glowOrigin(t: Double, stamps: [CreatureStamp]) -> Double {
        stamps.last(where: { $0.event == .memorySaved && $0.at + $0.event.duration <= t }).map { $0.at + $0.event.duration } ?? 0
    }

    /// One Z per breath, born 2.0 s into it (on the exhale), floating up and to the right, gone before the next.
    static func sleepZ(_ s: Double) -> [Creature.Sprite] {
        let local = max(0, zAge(s))
        guard zFloats(s) else { return [] }
        let p = Ease.Bezier(0.3, 0.1, 0.45, 1)(local / 2.6)
        let opacity = min(local / 0.3, 1) * min((2.6 - local) / 0.9, 1) * 0.72
        return [Creature.Sprite(pattern: zee, center: CGPoint(x: 15.8 + 1.8 * p, y: -1.3 - 2.4 * p), color: cream, opacity: opacity)]
    }

    static let glowSpots = [CGPoint(x: -1.2, y: 0.4), CGPoint(x: 8.5, y: -2.0), CGPoint(x: 17.2, y: 0.9)]

    /// Glowing: one sparkle at a time, a 0.5 s twinkle every 0.8 s, top, right, left.
    static let twinkleEvery = 0.8, twinkleLength = 0.5
    /// Where a twinkle changes shape, in seconds into it: dot, cross, star, cross, dot, gone (16, 20, 28, 20, 16%).
    static let twinkleSteps = [0, 0.16, 0.36, 0.64, 0.84, 1].map { $0 * twinkleLength }
    static func glowTwinkle(_ s: Double) -> [Creature.Sprite] {
        let s = s + epsilon   // stepped: a boundary counts as reached (see `epsilon`)
        guard s >= 0 else { return [] }
        let beat = Int(s / twinkleEvery), local = s - Double(beat) * twinkleEvery
        guard local < twinkleLength else { return [] }
        let i = [1, 2, 0][beat % 3]
        return [Creature.Sprite(pattern: sparkle(life: local / twinkleLength), center: glowSpots[i], color: i == 1 ? cream : light, opacity: 0.85)]
    }

    // MARK: Reactions

    static func react(_ e: CreatureEvent, tau: Double, base: LifeFrame, profile: LifeProfile) -> LifeFrame {
        var f = base
        switch e {
        case .memorySaved: hop(tau, &f.pose, &f.sprites, height: profile.hopHeight)
        case .accountOpened: wave(tau, &f.pose)
        case .error: startle(tau, &f.pose, &f.sprites)
        case .wake: wake(tau, &f.pose)
        case .doze: doze(tau, &f.pose)
        }
        return f
    }

    /// Memory saved: crouch, hop with the arms up, four sparkles burst at the apex and stay in the air, a springy landing.
    static func hop(_ tau: Double, _ pose: inout Creature.Pose, _ sprites: inout [Creature.Sprite], height H: Double) {
        pose.breath = 0; pose.look = 0; pose.eyeHeight = 1; pose.eyeBottom = 2
        var sx = 1.0, sy = 1.0, y = 0.0
        switch tau {
        case ..<0.08:                                    // anticipation: crouch
            let p = Ease.out(tau / 0.08)
            sy = 1 - 0.14 * p; sx = 1 + 0.10 * p
            pose.eyeHeight = 0.5
        case ..<0.30:                                    // takeoff and rise, gravity decelerating it
            let p = (tau - 0.08) / 0.22
            y = -H * (1 - (1 - p) * (1 - p))
            let snap = Ease.progress(tau, from: 0.08, over: 0.04)    // the squash flips into a stretch in 40 ms
            let relax = Ease.out(Ease.progress(tau, from: 0.12, over: 0.16))
            sy = Ease.lerp(0.86, 1.12 - 0.12 * relax, snap); sx = Ease.lerp(1.10, 0.92 + 0.08 * relax, snap)
        case ..<0.44:                                    // fall
            let p = (tau - 0.30) / 0.14
            y = -H * (1 - p * p)
        default:                                         // land: squash on contact, spring back, exactly 1 at the end
            let k = Ease.ringDown(tau - 0.44, response: 0.30, damping: 0.5) * (1 - Ease.progress(tau, from: 0.64, over: 0.10))
            sy = 1 - 0.12 * k; sx = 1 + 0.08 * k
        }
        pose.offset.dy = y
        pose.scaleX = sx; pose.scaleY = sy
        pose.legsTucked = tau >= 0.11 && tau < 0.44
        let arms: ArmPose = tau < 0.10 ? .rest : tau < 0.15 ? .lift1 : tau < 0.38 ? .up : tau < 0.47 ? .lift1 : .rest
        pose.armLeft = arms; pose.armRight = arms
        if tau >= 0.46, tau < 0.62 { pose.eyeHeight = 0.5 }     // a content squint after landing
        let start = CGPoint(x: 8, y: -H - 0.6)
        let travels = [CGPoint(x: -9.5, y: 0.4), CGPoint(x: -4.2, y: -2.0), CGPoint(x: 4.4, y: -2.2), CGPoint(x: 9.8, y: 0.6)]
        for (i, travel) in travels.enumerated() {
            let born = 0.20 + Double([1, 0, 2, 3][i]) * 0.03
            let life = (tau - born) / 0.46
            guard life >= 0, life < 1 else { continue }
            let p = Ease.out(life)
            sprites.append(Creature.Sprite(pattern: sparkle(life: life), center: CGPoint(x: start.x + travel.x * p, y: start.y + travel.y * p),
                                           color: i % 2 == 0 ? cream : light, opacity: life < 0.8 ? 1 : (1 - life) / 0.2))
        }
    }

    /// Account opened: a little bounce and a wave of the right arm, eyes smiling. `up` and `lift1` only: `out` alone reads as a tail.
    static func wave(_ tau: Double, _ pose: inout Creature.Pose) {
        pose.look = 0
        let swings: [(Double, ArmPose)] = [(0.05, .lift1), (0.17, .up), (0.27, .lift1), (0.37, .up), (0.47, .lift1), (0.53, .up), (0.58, .lift1)]
        pose.armRight = swings.first(where: { tau < $0.0 })?.1 ?? .rest
        if tau < 0.10 { pose.offset.dy = -0.5 * Ease.out(tau / 0.10) }
        else if tau < 0.20 { let p = (tau - 0.10) / 0.10; pose.offset.dy = -0.5 * (1 - p * p) }
        pose.eyeHeight = tau >= 0.04 && tau < 0.50 ? 0.5 : 1
        pose.eyeBottom = 2
    }

    /// Error: a startled jolt (eyes wide, hands thrown up), a damped shake, an exclamation mark, a relieved blink.
    static func startle(_ tau: Double, _ pose: inout Creature.Pose, _ sprites: inout [Creature.Sprite]) {
        pose.breath = 0; pose.look = 0; pose.eyeBottom = 2
        if tau < 0.05 { pose.offset.dy = -0.8 * Ease.out(tau / 0.05) }
        else if tau < 0.16 { let p = (tau - 0.05) / 0.11; pose.offset.dy = -0.8 * (1 - p * p) }
        else {
            let k = Ease.ringDown(tau - 0.16, response: 0.18, damping: 0.5) * (1 - Ease.progress(tau, from: 0.30, over: 0.10))
            pose.scaleY = 1 - 0.06 * k; pose.scaleX = 1 + 0.04 * k
            let s = tau - 0.16
            pose.offset.dx = 0.6 * exp(-4.5 * s) * sin(2 * .pi * 6 * s) * (1 - Ease.progress(tau, from: 0.56, over: 0.06))
        }
        pose.eyeHeight = tau < 0.40 ? 1.35 : (blink(tau - 0.56) ?? 1)
        let arms: ArmPose = tau < 0.02 ? .rest : tau < 0.16 ? .out : tau < 0.20 ? .lift1 : .rest
        pose.armLeft = arms; pose.armRight = arms
        if tau >= 0.03 {
            let pop = tau < 0.08 ? -0.5 : 0.0
            let opacity = tau < 0.50 ? 1.0 : max(0, 1 - (tau - 0.50) / 0.20)
            sprites.append(Creature.Sprite(pattern: bang, center: CGPoint(x: 17.4, y: -1.4 + pop), color: cream, opacity: opacity))
        }
    }

    /// Asleep to awake: the eyes open in two steps, a stretch with the arms up, a springy settle.
    static func wake(_ tau: Double, _ pose: inout Creature.Pose) {
        pose.look = 0
        if tau < 0.06 { (pose.eyeHeight, pose.eyeBottom) = Creature.Pose.asleepEyes }
        else { pose.eyeHeight = tau < 0.14 ? 0.5 : 1; pose.eyeBottom = 2 }
        let k: Double = tau < 0.14 ? Ease.out(tau / 0.14)
            : Ease.ringDown(tau - 0.14, response: 0.32, damping: 0.6) * (1 - Ease.progress(tau, from: 0.38, over: 0.08))
        pose.scaleY = 1 + 0.08 * k; pose.scaleX = 1 - 0.05 * k
        let arms: ArmPose = tau < 0.06 ? .rest : tau < 0.10 ? .lift1 : tau < 0.26 ? .up : tau < 0.30 ? .lift1 : .rest
        pose.armLeft = arms; pose.armRight = arms
    }

    /// Awake to asleep: heavy lids, then the asleep dash; the body sinks one device pixel and comes back. No scale.
    static func doze(_ tau: Double, _ pose: inout Creature.Pose) {
        pose.look = 0
        if tau < 0.18 { pose.eyeHeight = 1; pose.eyeBottom = 2 }
        else if tau < 0.46 { pose.eyeHeight = 0.5; pose.eyeBottom = 2 }
        else { (pose.eyeHeight, pose.eyeBottom) = Creature.Pose.asleepEyes }
        pose.breath = tau >= 0.30 && tau < 0.62 ? -1 : 0
    }

    // MARK: Reduce Motion

    /// Nothing moves: no breath, blink, glance or body motion. The eyes follow the state at once, and a reaction becomes a
    /// still cue that fades in and out (opacity only).
    public static func reducedFrame(state: CreatureState, t: Double, events: [CreatureStamp]) -> LifeFrame {
        var f = LifeFrame()
        if state == .asleep {
            f.pose = .asleep
            f.sprites.append(Creature.Sprite(pattern: zee, center: CGPoint(x: 16.2, y: -1.6), color: cream, opacity: 0.5))
        }
        if state == .glowing {
            f.sprites += glowSpots.enumerated().map {
                Creature.Sprite(pattern: sparkleFrames[1], center: $0.element, color: $0.offset == 1 ? cream : light, opacity: 0.7)
            }
        }
        guard let e = events.sorted(by: { $0.at < $1.at }).last(where: { t >= $0.at && t < $0.at + $0.event.duration }) else { return f }
        let tau = t - e.at, d = e.event.duration
        let opacity = min(tau / Theme.Motion.reducedDuration, 1) * min((d - tau) / Theme.Motion.reducedDuration, 1)
        switch e.event {
        case .memorySaved:
            f.sprites += [CGPoint(x: -1.6, y: -0.2), CGPoint(x: 8, y: -2.6), CGPoint(x: 17.6, y: -0.2)].map {
                Creature.Sprite(pattern: sparkleFrames[2], center: $0, color: cream, opacity: opacity)
            }
        case .error:
            f.sprites.append(Creature.Sprite(pattern: bang, center: CGPoint(x: 17.4, y: -1.4), color: cream, opacity: opacity))
        case .accountOpened, .wake, .doze:
            break   // the eyes already follow the state; the line beside the creature says the rest
        }
        return f
    }

    /// The events that show a cue under Reduce Motion (opacity only): the others change nothing but the eyes.
    static let reducedCues: [CreatureEvent] = [.memorySaved, .error]

    /// A reduced cue is fading: the one thing that needs frames under Reduce Motion.
    static func reducedCueRuns(t: Double, events: [CreatureStamp]) -> Bool {
        events.contains { reducedCues.contains($0.event) && t >= $0.at && t < $0.at + $0.event.duration }
    }

    /// A reaction or the walk is playing: what a window in the background still shows.
    static func reactionOrWalkRuns(t: Double, events: [CreatureStamp], walking: CreatureWalk?) -> Bool {
        effective(events, walking: walking).contains { t >= $0.at && t < $0.at + $0.event.duration } || walking?.isActive(at: t) == true
    }

    /// Where the idle comes to rest when it is held (a window in the background): the grid, or asleep without the Z.
    static func restingFrame(_ state: CreatureState) -> LifeFrame { LifeFrame(pose: state == .asleep ? .asleep : .rest) }

    // MARK: Scheduling

    /// True while something moves smoothly: a reaction, the walk, the Z floating up in the first minute asleep. Stepped
    /// content (blinks, glances, breath, the glow's twinkles) never needs them: `nextChange` finds each of its steps.
    public static func needsFrames(state: CreatureState, t: Double, events: [CreatureStamp], profile: LifeProfile,
                                   walking: CreatureWalk?, asleepSince: Double?) -> Bool {
        let stamps = effective(events, walking: walking)
        if stamps.contains(where: { t >= $0.at && t < $0.at + $0.event.duration }) { return true }
        if let walking, walking.isActive(at: t) { return true }
        guard state == .asleep else { return false }
        let s = t - (asleepSince ?? 0)
        return s >= 0 && s < sleepLoopEnd && zFloats(s)
    }

    /// The next time after `t` the frame changes, when nothing needs frames: a blink or glance step, a breath step, a
    /// twinkle's step, a Z's birth, a reaction or walk to come. Infinity when nothing will ever change (asleep after the
    /// first minute).
    public static func nextChange(after t: Double, state: CreatureState, events: [CreatureStamp], profile: LifeProfile, seed: UInt64 = 7,
                                  walking: CreatureWalk?, asleepSince: Double?) -> Double {
        let stamps = effective(events, walking: walking)
        let horizon = t + 30
        var candidates = stamps.map(\.at).filter { $0 > t }
        if let walking, walking.start > t { candidates.append(walking.start) }
        if state == .asleep, let since = asleepSince, since > t { candidates.append(since) }
        if state != .asleep {
            for b in blinks(from: t, to: horizon, profile: profile, seed: seed) {
                candidates += [b, b + 0.04, b + 0.10, b + blinkLength]
            }
            for g in glances(from: t - 1.5, to: horizon, profile: profile, seed: seed) {
                candidates += [g.start, g.start + g.end] + (g.double ? [g.start + 0.6] : [])
            }
            candidates += breathSteps(from: t, to: horizon, period: awakePeriod, amp: profile.awakeBreath)
        }
        if state == .glowing {
            let origin = glowOrigin(t: t, stamps: stamps)
            var beat = max(0, ((t - origin) / twinkleEvery).rounded(.down))
            while origin + beat * twinkleEvery <= horizon {
                candidates += twinkleSteps.map { origin + beat * twinkleEvery + $0 }
                beat += 1
            }
        }
        if state == .asleep, let since = asleepSince {
            // The first minute: the breath's steps and each Z's birth (it then floats, and needs frames). The loop ends on a
            // whole breath, the Z long gone: its end changes nothing.
            let end = since + sleepLoopEnd
            candidates += breathSteps(from: max(0, t - since), to: min(horizon, end) - since, period: sleepPeriod, amp: profile.sleepBreath)
                .map { $0 + since }
            candidates += stride(from: since + zBorn, to: end, by: sleepPeriod).map { $0 }
        }
        let here = frame(state: state, t: t, events: events, profile: profile, seed: seed, walking: walking, asleepSince: asleepSince)
        let future = candidates.filter { $0 > t }.sorted()
        for c in future {
            if needsFrames(state: state, t: c, events: events, profile: profile, walking: walking, asleepSince: asleepSince) { return c }
            if frame(state: state, t: c, events: events, profile: profile, seed: seed, walking: walking, asleepSince: asleepSince) != here { return c }
        }
        return future.isEmpty ? .infinity : horizon
    }

    /// The times in (a, b] the breath takes its next whole device pixel, found by bisection on each rising and falling half.
    static func breathSteps(from a: Double, to b: Double, period: Double, amp: Int) -> [Double] {
        guard amp > 0 else { return [] }
        var out: [Double] = []
        var n = (a / period).rounded(.down)
        while n * period <= b {
            for (lo0, hi0) in [(n * period, n * period + 0.42 * period), (n * period + 0.42 * period, (n + 1) * period)] {
                var lo = max(lo0, a)
                while lo < hi0 {
                    let v = breath(lo, period: period, amp: amp)
                    // The last moment of this half: a whole period's end folds back to 0, so stop just before it.
                    let end = hi0 - 1e-9
                    guard breath(end, period: period, amp: amp) != v else { break }
                    var l = lo, h = end
                    for _ in 0..<60 {
                        let m = (l + h) / 2
                        if breath(m, period: period, amp: amp) == v { l = m } else { h = m }
                    }
                    if h > a, h <= b { out.append(h) }
                    lo = h
                }
            }
            n += 1
        }
        return out
    }
}

/// The creature's timeline: 60 dates a second only while something moves smoothly (a reaction, the walk, the Z floating up
/// in the first minute asleep), otherwise one date per stepped change (`nextChange`: blinks, glances, breath, the glow's
/// twinkles), and a far-future wait once nothing will change. Captures and `.lowFrequency` show one still; Reduce Motion
/// wakes only for its fading cues.
///
/// A window in the background plays reactions and the walk but holds the idle (Ruben's call: a save's hop seen in the
/// background is wanted, where the motion spec first asked for a full pause). The sidebar's moments happen while another
/// app is in front (an opened account's window comes forward, Claude Code saves the memory): paused, the creature would never
/// be seen walking, waving or hopping. Each is bounded (under 0.8 s, the walk until the opening ends) and ends on its resting
/// frame; the endless parts (blinks, glances, the sleep loop) hold still.
public struct CreatureSchedule: TimelineSchedule {
    public enum Mode: Equatable, Sendable {
        case live, background, reduced, still
        /// Captures show the still; Reduce Motion its cues; a window in the background its reactions; otherwise the life.
        public init(capture: Bool, reduceMotion: Bool, active: Bool) {
            self = capture ? .still : reduceMotion ? .reduced : active ? .live : .background
        }
    }
    public var start: Date
    public var mode: Mode
    public var state: CreatureState
    public var events: [CreatureStamp]
    public var profile: LifeProfile
    public var seed: UInt64 = 7
    public var walking: CreatureWalk?
    public var asleepSince: Double?
    /// BRAINMERGE_SLOW_MOTION: scene time runs this many times slower than the clock.
    public var slow: Double = Theme.Motion.slow

    public init(start: Date, mode: Mode, state: CreatureState, events: [CreatureStamp], profile: LifeProfile, seed: UInt64 = 7,
                walking: CreatureWalk?, asleepSince: Double?, slow: Double = Theme.Motion.slow) {
        self.start = start; self.mode = mode; self.state = state; self.events = events; self.profile = profile; self.seed = seed
        self.walking = walking; self.asleepSince = asleepSince; self.slow = max(1, slow)
    }

    static let frameInterval = 1.0 / 60
    /// A stepped change's date is taken half a millisecond late: `date - start` is not exact at real clock values, and the
    /// frame drawn at that date must already show the change.
    static let lateBy = 0.0005

    /// Scene time at a date, in seconds on the view's clock.
    public func time(at date: Date) -> Double { date.timeIntervalSince(start) / slow }
    /// The model's dated stamps on the view's clock.
    public static func stamps(_ moments: [CreatureMoment], since start: Date, slow: Double = Theme.Motion.slow) -> [CreatureStamp] {
        moments.map { CreatureStamp($0.event, at: $0.date.timeIntervalSince(start) / max(1, slow)) }
    }

    /// What the view draws at a date.
    public func frame(at date: Date) -> LifeFrame {
        let t = time(at: date)
        switch mode {
        case .still: return CreatureLife.reducedFrame(state: state, t: 0, events: [])
        case .reduced: return CreatureLife.reducedFrame(state: state, t: t, events: events)
        case .background where !CreatureLife.reactionOrWalkRuns(t: t, events: events, walking: walking):
            return CreatureLife.restingFrame(state)
        case .live, .background:
            return CreatureLife.frame(state: state, t: t, events: events, profile: profile, seed: seed, walking: walking, asleepSince: asleepSince)
        }
    }

    /// What the view draws at a date, at the timeline's cadence. A timeline held at a low frequency draws one date and
    /// waits, and that date may fall mid-reaction: held, it shows the resting pose (or, under Reduce Motion and in captures,
    /// the state's still), never a hop frozen in the air.
    public func frame(at date: Date, cadence: TimelineViewDefaultContext.Cadence) -> LifeFrame {
        guard cadence != .live else { return frame(at: date) }
        switch mode {
        case .still, .reduced: return CreatureLife.reducedFrame(state: state, t: 0, events: [])
        case .live, .background: return CreatureLife.restingFrame(state)
        }
    }

    /// The entry after `date`, or nil when nothing will change (the entries then wait, see `Entries`).
    func nextDate(after date: Date) -> Date? {
        let t = time(at: date)
        let next: Double
        switch mode {
        case .still:
            return nil
        case .live:
            if CreatureLife.needsFrames(state: state, t: t, events: events, profile: profile, walking: walking, asleepSince: asleepSince) {
                return date.addingTimeInterval(Self.frameInterval)
            }
            next = CreatureLife.nextChange(after: t, state: state, events: events, profile: profile, seed: seed, walking: walking, asleepSince: asleepSince)
        case .background:
            if CreatureLife.reactionOrWalkRuns(t: t, events: events, walking: walking) { return date.addingTimeInterval(Self.frameInterval) }
            let starts = CreatureLife.effective(events, walking: walking).map(\.at) + [walking?.start].compactMap { $0 }
            next = starts.filter { $0 > t }.min() ?? .infinity
        case .reduced:
            if CreatureLife.reducedCueRuns(t: t, events: events) { return date.addingTimeInterval(Self.frameInterval) }
            next = events.filter { CreatureLife.reducedCues.contains($0.event) && $0.at > t }.map(\.at).min() ?? .infinity
        }
        guard next.isFinite else { return nil }
        let at = start.addingTimeInterval(next * slow + Self.lateBy)
        return max(at, date.addingTimeInterval(0.001))
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(schedule: self, pending: startDate, paused: mode == .lowFrequency)
    }

    /// The dates, then a wait on a far-future date once nothing will change: SwiftUI never draws a schedule's last entry, so
    /// without it the frame that stays (landed, asleep, faded out) would never be drawn and the last moving one would stick.
    public struct Entries: Sequence, IteratorProtocol {
        let schedule: CreatureSchedule
        var pending: Date?
        let paused: Bool
        public mutating func next() -> Date? {
            guard let date = pending else { return nil }
            if date == .distantFuture { pending = nil; return date }
            pending = (paused ? nil : schedule.nextDate(after: date)) ?? .distantFuture
            return date
        }
    }
}
