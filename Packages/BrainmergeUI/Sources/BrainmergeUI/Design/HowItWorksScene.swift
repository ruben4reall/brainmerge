import CoreGraphics
import Foundation
import BrainmergeCore

/// How it works, step two of the guided setup: three account windows along the top, one memory folder on this Mac below
/// them, the creature standing beside it. Each beat, one account's Claude Code types a note; the note lifts out of its
/// window as a page, drops into the folder, and copies of it rise into the two other windows.
///
/// A pure function of time, `frame(at:)`: no views, no clock. HowItWorksView draws its frames; Reduce Motion and captures
/// draw `still()`. Nothing here moves between accounts except through the folder on this Mac, and the windows never move.
public enum HowItWorksScene {
    /// The canvas, in points, drawn 1:1 and never scaled (the creature's 3 pt cells stay whole).
    public static let size = CGSize(width: 520, height: 224)
    public static let beat = 3.0
    public static let loop = beat * 3

    public struct Account: Sendable, Equatable { public let name: String; public let tint: Tint }
    /// Personal, Work, Studio: Studio is pink as everywhere else in the product, and Work sits between the two warm tints.
    public static let accounts = [Account(name: "Personal", tint: .orange), Account(name: "Work", tint: .blue),
                                  Account(name: "Studio", tint: .pink)]
    /// Which account writes in each beat.
    public static let order = [0, 1, 2]

    // MARK: Layout (points, in the 520 by 224 canvas)

    public static let windowSize = CGSize(width: 144, height: 66)
    public static let windowTop: CGFloat = 8
    public static let windowCenters: [CGFloat] = [88, 260, 432]
    public static func windowRect(_ i: Int) -> CGRect {
        CGRect(x: windowCenters[i] - windowSize.width / 2, y: windowTop, width: windowSize.width, height: windowSize.height)
    }
    /// The folder's back panel, tab excluded, and the top of its front panel.
    public static let folderRect = CGRect(x: 208, y: 138, width: 104, height: 62)
    public static let folderFrontTop: CGFloat = 151
    public static let creatureFeet = CGPoint(x: 350, y: 200)
    public static let creatureUnit: CGFloat = 3
    /// Where a lane meets the folder.
    public static let slotY: CGFloat = 140
    /// The row inside a window that shows the last note it received.
    public static let receivedRowY: CGFloat = windowTop + 50
    /// The caption, under the creature's shadow with 4 points of air.
    public static let captionCenter = CGPoint(x: 260, y: 216)
    public static let captionFontSize: CGFloat = 11.5

    /// The lane from window i to the folder's slot: it starts inside the window (hidden under it) and ends at the slot.
    public static let lanes: [ArcPath] = [
        ArcPath(CGPoint(x: 82, y: 41), CGPoint(x: 86, y: 122), CGPoint(x: 236, y: 92), CGPoint(x: 240, y: slotY)),
        ArcPath(CGPoint(x: 254, y: 41), CGPoint(x: 260, y: 96), CGPoint(x: 260, y: 110), CGPoint(x: 260, y: slotY)),
        ArcPath(CGPoint(x: 426, y: 41), CGPoint(x: 430, y: 122), CGPoint(x: 284, y: 92), CGPoint(x: 280, y: slotY)),
    ]
    /// The fraction of a lane where it first reaches the height `y`, in `step`s.
    static func fraction(onLane i: Int, atY y: CGFloat, step: Double) -> Double {
        var s = 0.0
        while s < 0.5, lanes[i].point(atFraction: s).y < y { s += step }
        return s
    }
    /// Where each lane comes out from under its window (the drawn line starts there) and where a copy stops, at the row
    /// of received notes. Computed once: they are constants of the layout.
    public static let laneVisibleStart: [Double] = lanes.indices.map { fraction(onLane: $0, atY: windowTop + windowSize.height + 1, step: 0.005) }
    public static let laneReceivedFraction: [Double] = lanes.indices.map { fraction(onLane: $0, atY: receivedRowY, step: 0.002) }

    // MARK: Beat timing (seconds inside a beat)

    public enum T {
        public static let activeIn = 0.0, typeStart = 0.12, typeStep = 0.07, blocks = 6
        /// The note leaves the window.
        public static let lift = 0.56
        /// From the slot into the folder.
        public static let drop = 0.14
        public static let copyRise = 0.12, stagger = 0.09
        public static let trailFadeStart = 2.3, trailFade = 0.4
        public static let activeOut = 2.62
        /// Captures and Reduce Motion: beat 0 at this time.
        public static let hero = 1.97
        /// Travel time grows with the lane's length, so the speed looks the same on the short middle lane: a base plus one
        /// second per `speed` points.
        public static let travelBase = 0.42, copyBase = 0.36, speed = 620.0
    }

    /// One beat's timing, from the lanes' lengths: the note's flight, its landing, each copy's departure and arrival.
    public struct Timing: Sendable, Equatable {
        public let travel: Double, arrive: Double, landed: Double, copyStart: Double
        /// Per destination, in `destinations(of:)` order.
        public let copyTravel: [Double], copyLeave: [Double], copyArrive: [Double]
    }
    public static func destinations(of src: Int) -> [Int] { [0, 1, 2].filter { $0 != src } }
    public static func timing(src: Int) -> Timing { timings[src] }
    private static let timings: [Timing] = accounts.indices.map { src in
        let dests = destinations(of: src)
        let travel = T.travelBase + lanes[src].length / T.speed
        let arrive = T.lift + travel, landed = arrive + T.drop
        let copyStart = landed + 0.08
        let copyTravel = dests.map { T.copyBase + lanes[$0].length * (1 - laneReceivedFraction[$0]) / T.speed }
        let leave = dests.indices.map { copyStart + Double($0) * T.stagger }
        let arrives = dests.indices.map { leave[$0] + T.copyRise + copyTravel[$0] }
        return Timing(travel: travel, arrive: arrive, landed: landed, copyStart: copyStart, copyTravel: copyTravel,
                      copyLeave: leave, copyArrive: arrives)
    }

    // MARK: Captions

    static func savesCaption(_ src: Int) -> String { "\(accounts[src].name) saves a note" }
    static func readsCaption(_ src: Int) -> String {
        let d = destinations(of: src)
        return "\(accounts[d[0]].name) and \(accounts[d[1]].name) can read it"
    }
    static let stillCaption = "Personal saves a note. Work and Studio can read it."
    /// Every caption the scene can show: HowItWorksView lays each one out once.
    public static let captions: [String] = accounts.indices.flatMap { [savesCaption($0), readsCaption($0)] } + [stillCaption]

    // MARK: The frame

    /// A note page in flight. `source` is the account that wrote it (its tint).
    public struct Chip: Sendable, Equatable {
        public var position: CGPoint
        public var rotation: Double
        public var scale: Double
        public var opacity: Double
        public var source: Int
        /// Inside the folder: drawn between its back and its front.
        public var behindFront: Bool
    }
    public struct WindowState: Sendable, Equatable {
        /// 0 the neutral rim, 1 lit in `outlineSource`'s tint.
        public var outline: Double = 0
        public var outlineSource: Int?
        /// Blocks typed on the prompt line.
        public var typed = 0
        public var typedOpacity = 1.0
        public var cursor = false
        /// The account whose note this window received last, from this beat or an earlier one.
        public var received: Int?
        public var receivedOpacity = 1.0
        /// Points: the new row rises into place.
        public var receivedRise = 0.0
        /// The row it replaces, fading out.
        public var previous: Int?
        public var previousOpacity = 0.0
        /// The arrival ring's progress, 0 to 1, in `ringSource`'s tint.
        public var ring: Double?
        public var ringSource: Int?
    }
    /// A lane lit by a note: from one fraction of its length to another, in the writer's tint.
    public struct Trail: Sendable, Equatable {
        public var lane: Int
        public var from: Double
        public var to: Double
        public var opacity: Double
        public var source: Int
    }
    public struct Frame: Sendable, Equatable {
        public var windows = [WindowState](repeating: WindowState(), count: 3)
        public var trails: [Trail] = []
        public var chips: [Chip] = []
        /// The folder's front panel dips as a note lands, anchored at its bottom.
        public var frontSquash = 0.0
        /// Its rim flashes.
        public var folderFlash = 0.0
        public var creature = Creature.Pose.rest
        public var caption = ""
        public var captionOpacity = 1.0
        /// Points: a new caption rises into place.
        public var captionRise = 0.0
    }

    /// Captures and Reduce Motion: one still that tells the whole story, beat 0 at `T.hero` with both halves of the caption.
    /// Personal's rim is lit and its lane drawn in orange, the copies are on their way to Work and Studio, the creature rests
    /// on its exact grid (the hop's last hundredth of squash is dropped) and watches the first copy go.
    public static func still() -> Frame {
        var f = frame(at: T.hero)
        f.caption = stillCaption
        f.captionOpacity = 1
        f.captionRise = 0
        var watching = Creature.Pose.rest
        watching.look = f.creature.look
        f.creature = watching
        return f
    }

    public static func frame(at time: Double) -> Frame {
        let t = (time.truncatingRemainder(dividingBy: loop) + loop).truncatingRemainder(dividingBy: loop)
        let beatIndex = min(Int(t / beat), 2)
        let tau = t - Double(beatIndex) * beat
        let src = order[beatIndex]
        let dests = destinations(of: src)
        let tm = timing(src: src)
        var f = Frame()

        receivedNotes(&f, beatIndex: beatIndex, tau: tau)

        // The writing window: its rim takes its tint, the prompt types, then the note lifts out.
        var sw = f.windows[src]
        sw.outline = Ease.envelope(tau, start: T.activeIn, rise: 0.22, end: T.activeOut + 0.2, fall: 0.3)
        sw.outlineSource = src
        let typedCount = Int(((tau - T.typeStart) / T.typeStep).rounded(.down)) + 1
        sw.typed = max(0, min(T.blocks, typedCount))
        sw.cursor = tau >= T.typeStart - 0.06 && tau < T.lift
        sw.typedOpacity = 1 - Ease.ease(Ease.progress(tau, from: T.lift, over: 0.18))
        f.windows[src] = sw
        // The receiving windows glow in the writer's tint when their copy lands.
        for (k, d) in dests.enumerated() {
            let arrive = tm.copyArrive[k]
            let glow = Ease.envelope(tau, start: arrive - 0.05, rise: 0.12, end: arrive + 0.3, fall: 0.25)
            if glow > f.windows[d].outline { f.windows[d].outline = glow * 0.8; f.windows[d].outlineSource = src }
        }

        // The note pops out of the prompt row, flies its lane at an even speed, and drops into the folder.
        let lane = lanes[src]
        if tau >= T.lift - 0.02 && tau < tm.landed + 0.02 {
            let p = Ease.progress(tau, from: T.lift, over: tm.travel)
            let s = Ease.glide(p)
            var position = lane.point(atFraction: s)
            var rotation = 16 * Double(lane.tangent(atFraction: s).dx) * sin(Double.pi * p)   // banks into the curve
            var scale = 0.7 + 0.3 * Ease.spring(tau - (T.lift - 0.02), response: 0.34, damping: 0.62)
            var behind = false
            if tau > tm.arrive {
                let d = Ease.progress(tau, from: tm.arrive, over: T.drop)
                position.y = slotY + 22 * d * d                  // falls in, accelerating
                rotation *= 1 - d
                scale = 1 - 0.12 * d
                behind = true
            }
            let opacity = Ease.out(Ease.progress(tau, from: T.lift - 0.02, over: 0.1))
            f.chips.append(Chip(position: position, rotation: rotation, scale: scale, opacity: opacity, source: src, behindFront: behind))
        }
        // Its trail draws itself behind it, in the writer's tint, and fades once the copies are home.
        if tau >= T.lift {
            let p = Ease.progress(tau, from: T.lift, over: tm.travel)
            let fade = 1 - Ease.ease(Ease.progress(tau, from: T.trailFadeStart, over: T.trailFade))
            f.trails.append(Trail(lane: src, from: laneVisibleStart[src], to: Ease.glide(p), opacity: 0.85 * fade, source: src))
        }
        // The folder takes the note: its front dips and its rim flashes.
        f.frontSquash = 0.07 * Ease.impulse(tau - tm.landed + 0.03, response: 0.32, damping: 0.42)
        if abs(f.frontSquash) < 0.0005 { f.frontSquash = 0 }
        f.folderFlash = Ease.envelope(tau, start: tm.landed - 0.04, rise: 0.06, end: tm.landed + 0.5, fall: 0.4)

        copies(&f, tau: tau, src: src, dests: dests, tm: tm)
        f.creature = creaturePose(tau: tau, beatIndex: beatIndex, src: src, dests: dests, chips: f.chips, tm: tm)

        // One caption per half beat: who saves, then who can read it.
        let cut = tm.copyStart - 0.05
        let second = tau >= cut
        f.caption = second ? readsCaption(src) : savesCaption(src)
        let local = second ? tau - cut : tau
        let span = second ? beat - cut : cut
        f.captionOpacity = Ease.envelope(local, start: 0, rise: 0.2, end: span, fall: 0.14)
        f.captionRise = 3 * (1 - Ease.out(Ease.progress(local, from: 0, over: 0.28)))
        return f
    }

    /// Received notes persist: each window shows the last note it received, from this beat or the two before (cyclic), so
    /// the loop has no seam.
    private static func receivedNotes(_ f: inout Frame, beatIndex: Int, tau: Double) {
        for w in 0..<3 {
            var history: [(age: Double, source: Int)] = []
            for back in 0..<3 {
                let s = order[(beatIndex - back + 3) % 3]
                guard s != w, let slot = destinations(of: s).firstIndex(of: w) else { continue }
                let arrive = timing(src: s).copyArrive[slot]
                let local = tau + Double(back) * beat
                if local >= arrive { history.append((local - arrive, s)) }
            }
            history.sort { $0.age < $1.age }
            guard let last = history.first else {
                // Before any arrival in this loop: the last note of the loop before (Studio's, or Work's for Studio).
                f.windows[w].received = w == 2 ? 1 : 2
                continue
            }
            f.windows[w].received = last.source
            f.windows[w].receivedOpacity = Ease.out(Ease.progress(last.age, from: 0.06, over: 0.24))
            f.windows[w].receivedRise = 4 * (1 - Ease.out(Ease.progress(last.age, from: 0.06, over: 0.32)))
            if history.count > 1 {
                f.windows[w].previous = history[1].source
                f.windows[w].previousOpacity = 1 - Ease.ease(Ease.progress(last.age, from: 0, over: 0.12))
            }
            if last.age < 0.5 { f.windows[w].ring = last.age / 0.5; f.windows[w].ringSource = last.source }
        }
    }

    /// Two copies rise out of the folder and fly up to the other windows, their trails lit in the writer's tint.
    private static func copies(_ f: inout Frame, tau: Double, src: Int, dests: [Int], tm: Timing) {
        for (k, d) in dests.enumerated() {
            let start = tm.copyLeave[k], arrive = tm.copyArrive[k]
            let lane = lanes[d]
            let endS = laneReceivedFraction[d]
            if tau >= start && tau < arrive + 0.16 {
                var position: CGPoint, rotation = 0.0, behind = false
                if tau < start + T.copyRise {
                    let r = Ease.out(Ease.progress(tau, from: start, over: T.copyRise))
                    position = CGPoint(x: lane.p3.x, y: slotY + 20 * (1 - r))
                    behind = true
                } else {
                    let p = Ease.progress(tau, from: start + T.copyRise, over: tm.copyTravel[k])
                    let s = 1 - (1 - endS) * Ease.glide(p)
                    position = lane.point(atFraction: s)
                    rotation = -16 * Double(lane.tangent(atFraction: s).dx) * sin(Double.pi * p)
                }
                let fadeIn = Ease.out(Ease.progress(tau, from: start, over: 0.08))
                let absorb = Ease.progress(tau, from: arrive - 0.02, over: 0.16)
                let scale = (0.86 + 0.14 * Ease.spring(tau - start, response: 0.3, damping: 0.7)) * (1 - 0.35 * Ease.out(absorb))
                f.chips.append(Chip(position: position, rotation: rotation, scale: scale, opacity: fadeIn * (1 - absorb), source: src,
                                    behindFront: behind))
            }
            if tau >= start + T.copyRise {
                let p = Ease.progress(tau, from: start + T.copyRise, over: tm.copyTravel[k])
                let fade = 1 - Ease.ease(Ease.progress(tau, from: T.trailFadeStart + 0.2, over: T.trailFade))
                f.trails.append(Trail(lane: d, from: max(laneVisibleStart[d], 1 - (1 - endS) * Ease.glide(p)), to: 1,
                                      opacity: 0.85 * fade, source: src))
            }
        }
    }

    // MARK: The creature

    /// The creature watches the window that types, follows the note, cheers when it lands (a hop in beats 0 and 2, a catch
    /// in beat 1, so the loop never feels canned), then watches the first copy leave. Every beat ends exactly at rest.
    static func creaturePose(tau: Double, beatIndex: Int, src: Int, dests: [Int], chips: [Chip], tm: Timing) -> Creature.Pose {
        var pose = Creature.Pose()
        let eyeX = creatureFeet.x
        func look(at p: CGPoint) {
            let dx = p.x - eyeX
            pose.look = abs(dx) < 14 ? 0 : (dx < 0 ? -1 : 1)   // whole cells, never toward row 0
        }
        if tau >= 0.3 && tau < T.lift { look(at: CGPoint(x: windowCenters[src], y: 40)) }
        if tau >= T.lift && tau < tm.landed, let note = chips.first { look(at: note.position) }
        if tau >= tm.landed && tau < tm.copyStart + 0.1 { pose.look = -1 }
        if tau >= tm.copyStart + 0.1 && tau < tm.copyArrive[0] + 0.25 {
            let p = Ease.progress(tau, from: tm.copyStart + T.copyRise, over: tm.copyTravel[0])
            look(at: lanes[dests[0]].point(atFraction: 1 - Ease.glide(p)))
        }

        let land = tm.landed + 0.02
        if beatIndex == 1 {
            // The catch: arms up, a squash that rings down.
            if tau >= land - 0.06 && tau < land + 0.42 { pose.armLeft = .lift1; pose.armRight = .lift1 }
            let k = Ease.impulse(tau - land, response: 0.34, damping: 0.45)
            pose.scaleY = 1 - 0.1 * k
            pose.scaleX = 1 + 0.06 * k
        } else {
            let anticipation = 0.08, air = 0.26
            let a = tau - (land - anticipation)
            if a >= 0 && a < anticipation {
                let k = sin(Double.pi / 2 * a / anticipation)          // the wind-up squash
                pose.scaleY = 1 - 0.1 * k
                pose.scaleX = 1 + 0.07 * k
            } else if a >= anticipation && a < anticipation + air {
                let u = (a - anticipation) / air
                pose.offset.dy = -hopHeight * 4 * u * (1 - u) / creatureUnit   // a parabola: gravity
                let stretch = max(0, 1 - u * 2.2)
                pose.scaleY = 1 + 0.08 * stretch
                pose.scaleX = 1 - 0.05 * stretch
                pose.legsTucked = u > 0.12 && u < 0.85
                pose.armLeft = .lift1; pose.armRight = .lift1
            } else if a >= anticipation + air {
                let k = Ease.impulse(a - anticipation - air, response: 0.3, damping: 0.5)
                pose.scaleY = 1 - 0.1 * k
                pose.scaleX = 1 + 0.06 * k
                if a < anticipation + air + 0.1 { pose.armLeft = .lift1; pose.armRight = .lift1 }
            }
        }
        // Blinks at fixed times: once in beat 0, a double blink in beat 2.
        func blink(_ at: Double) {
            let d = tau - at
            if d >= 0 && d < 0.14 { pose.eyeHeight = d < 0.04 || d >= 0.10 ? 0.5 : 0.15 }
        }
        if beatIndex == 0 { blink(2.66) }
        if beatIndex == 2 { blink(0.14); blink(0.46) }
        // Springs settle asymptotically: their last fifth of a percent snaps to the exact rest pose.
        if abs(pose.scaleX - 1) < 0.002 { pose.scaleX = 1 }
        if abs(pose.scaleY - 1) < 0.002 { pose.scaleY = 1 }
        return pose
    }

    /// The hop's apex, in points.
    public static let hopHeight: CGFloat = 7

    /// How high the creature is, 0 on the ground to 1 at the hop's apex.
    public static func air(of pose: Creature.Pose) -> Double { Double(min(1, max(0, -pose.offset.dy * creatureUnit / hopHeight))) }
    /// The flat shadow under the feet: 12 cells wide on the ground, 8 at the apex.
    public static func shadowRect(air: Double) -> CGRect {
        let width = creatureUnit * CGFloat(12 - 4 * air)
        return CGRect(x: creatureFeet.x - width / 2, y: creatureFeet.y + 2, width: width, height: 3)
    }
    /// The shadow's opacity (over `Colors.selection`): lighter while the creature is in the air.
    public static func shadowOpacity(air: Double) -> Double { 1 - 0.35 * air }
}
