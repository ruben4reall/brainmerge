import SwiftUI

public enum CreatureState: Equatable, Sendable { case asleep, awake, glowing }

/// The creature: a 16 by 11 grid (body, two arms, four legs), in purple. A single file, easy to replace.
public enum Creature {
    public static let columns = 16
    public static let rows = 11
    static let body: [String] = [
        "..XXXXXXXXXXXX..",
        "..XXXXXXXXXXXX..",
        "..XXXXXXXXXXXX..",
        "XXXXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXXXX",
        "..XXXXXXXXXXXX..",
        "..XXXXXXXXXXXX..",
        "..X..X....X..X..",
        "..X..X....X..X..",
        "..X..X....X..X..",
    ]
    public struct Pixel: Hashable, Sendable { public let x: Int; public let y: Int; public init(x: Int, y: Int) { self.x = x; self.y = y } }
    public struct Eye: Equatable, Sendable { public let x: Int; public let y: Int; public let height: CGFloat }

    public static func bodyPixels() -> [Pixel] {
        body.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, ch in ch == "X" ? Pixel(x: x, y: y) : nil }
        }
    }

    /// Eyes open (squares) when awake or glowing; closed (dashes) when asleep, one line lower.
    public static func eyes(for state: CreatureState) -> [Eye] {
        switch state {
        case .asleep: return [Eye(x: 4, y: 2, height: 0.35), Eye(x: 11, y: 2, height: 0.35)]
        case .awake, .glowing: return [Eye(x: 4, y: 1, height: 1), Eye(x: 11, y: 1, height: 1)]
        }
    }

    /// The legs: the columns filled on the grid's last row.
    static var legColumns: [Int] { body.last.map { filled($0) } ?? [] }
    /// The first leg row: going up from the bottom, the rows that hold nothing but the legs.
    static var legTop: Int {
        let legs = Set(legColumns)
        var top = body.count
        while top > 0, Set(filled(body[top - 1])).isSubset(of: legs) { top -= 1 }
        return top
    }
    /// The arms: the pixels outside the columns row 0 fills (the head's width).
    static var armColumns: Set<Int> { Set(0..<columns).subtracting(body.first.map { filled($0) } ?? []) }
    private static func filled(_ row: String) -> [Int] { row.enumerated().compactMap { $1 == "X" ? $0 : nil } }

    // MARK: The walk, computed from the grid: a new grid walks without new drawings.

    /// The frames of one step: contact, first legs lifted, contact, the other legs lifted.
    public static let walkCycle = 4

    /// Frame `index` of the walk, any integer (it loops). Contact frames (even) are the rest pose, every foot on the ground;
    /// on the passing frames the body is up one row, half the legs stay planted and stretch to the ground, the other half
    /// are lifted, alternating, and the arm on the side of the lifted front leg swings up one row.
    public static func walkFrame(_ index: Int) -> Pose {
        let phase = ((index % walkCycle) + walkCycle) % walkCycle
        guard phase % 2 == 1 else { return .rest }
        var pose = Pose()
        pose.raise = 1
        pose.liftedLegs = legColumns.indices.map { ($0 % 2 == 0) == (phase == 1) }
        if phase == 1 { pose.armRight = .lift1 } else { pose.armLeft = .lift1 }
        return pose
    }

    /// The columns of the walk's flat shadow: under every foot on contact, one column narrower on each side while the body is up.
    public static func walkShadow(_ index: Int) -> ClosedRange<Int> {
        let legs = legColumns
        guard let left = legs.min(), let right = legs.max() else { return 0...0 }
        let inset = walkFrame(index) == .rest ? 0 : 1
        return (left + inset)...max(left + inset, right - inset)
    }

    /// The frame shown at `date` for a walk started at `start`: one frame per `frameDuration`, looping; frame 0 when frozen
    /// (Reduce Motion) or before the start. A tick's date minus the start is not exact at real clock values (about 7.8e8 s),
    /// so a date a hair before its tick still counts as that tick: a plain division repeats and skips frames.
    public static func walkIndex(at date: Date, since start: Date, frameDuration: TimeInterval, frozen: Bool) -> Int {
        guard !frozen, frameDuration > 0 else { return 0 }
        let ticks = (date.timeIntervalSince(start) / frameDuration + 0.001).rounded(.down)
        guard ticks.isFinite, ticks > 0 else { return 0 }
        return Int(ticks.truncatingRemainder(dividingBy: Double(walkCycle)))
    }
}

/// The poses an arm can take, as pixels of the RIGHT arm (columns 14 and up); the left arm is the mirror (x to 15 - x).
/// Rest is exactly the grid; the others exist only mid-motion.
public enum ArmPose: Sendable, Equatable {
    case rest, lift1, up, out
    public var pixels: [Creature.Pixel] {
        let cells: [(Int, Int)]
        switch self {
        case .rest: cells = [(14, 3), (15, 3), (14, 4), (15, 4), (14, 5), (15, 5)]
        case .lift1: cells = [(14, 2), (15, 2), (14, 3), (15, 3), (14, 4), (15, 4)]
        // Raised beside the head with one column of air, so it reads as an arm, not a wider head.
        case .up: cells = [(14, 3), (15, 3), (15, 2), (16, 2), (15, 1), (16, 1)]
        // Thrown up and out: the startle only, always on both arms (alone, the diagonal reads as a tail).
        case .out: cells = [(14, 3), (15, 3), (15, 2), (16, 2), (16, 1), (17, 1)]
        }
        return cells.map { Creature.Pixel(x: $0.0, y: $0.1) }
    }
}

/// One body pixel on its way home (the launch's gather): offset in cells from its home, its own size and opacity.
public struct PixelState: Sendable, Equatable {
    public var dx: CGFloat = 0, dy: CGFloat = 0
    public var scale: CGFloat = 1
    public var opacity: Double = 1
    public init(dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1, opacity: Double = 1) {
        self.dx = dx; self.dy = dy; self.scale = scale; self.opacity = opacity
    }
    public var isHome: Bool { abs(dx) < 0.001 && abs(dy) < 0.001 && abs(scale - 1) < 0.001 && opacity >= 0.999 }
}

public extension Creature {
    /// Everything a frame of the creature can vary. At its defaults it draws exactly the grid.
    struct Pose: Equatable, Sendable {
        /// Grid cells; snapped to device pixels when drawn.
        public var offset: CGVector = .zero
        /// Squash and stretch, anchored at the middle of the feet, grid (8, 11).
        public var scaleX: CGFloat = 1, scaleY: CGFloat = 1
        /// Degrees; only the leap uses it.
        public var rotation: Double = 0
        /// The walk: the body up whole rows, the planted legs stretch to the ground.
        public var raise: Int = 0
        /// DEVICE pixels: the body above the legs rises, the top leg row stretches to stay on the ground.
        public var breath: Int = 0
        /// The walk's passing frames: that leg's bottom row is gone (legs in `legColumns` order).
        public var liftedLegs: [Bool] = [false, false, false, false]
        /// Airborne: the bottom row is gone on every leg.
        public var legsTucked = false
        public var armLeft: ArmPose = .rest, armRight: ArmPose = .rest
        /// Stepped: 1, 0.5, 0.2, 0.15; 1.35 in the startle (grows upward); 0 draws no eyes (the launch's gather).
        public var eyeHeight: CGFloat = 1
        /// The grid row of the eye's bottom edge; the asleep dash is 0.35 high with its bottom at 2.35.
        public var eyeBottom: CGFloat = 2
        /// Whole cells, -1...1, horizontal only: the eyes never move to row 0.
        public var look: Int = 0
        public var opacity: Double = 1
        /// The launch's gather only, in `bodyPixels()` order.
        public var pixels: [PixelState]? = nil

        public init(offset: CGVector = .zero) { self.offset = offset }

        public static let rest = Pose()
        /// The rest pose with the asleep dash.
        public static let asleep: Pose = {
            var pose = Pose()
            pose.eyeHeight = asleepEyes.height
            pose.eyeBottom = asleepEyes.bottom
            return pose
        }()
        static let asleepEyes: (height: CGFloat, bottom: CGFloat) = (0.35, 2.35)
    }

    /// A small pixel sprite drawn around the creature (a sparkle, a Z, an exclamation mark), on a half-cell grid.
    /// `center` is in world cells: grid coordinates of the creature at rest, never following its offset.
    struct Sprite: Equatable, Sendable {
        public var pattern: [String]
        public var center: CGPoint
        public var pixel: CGFloat = 0.5
        public var color: Color
        public var opacity: Double
        public init(pattern: [String], center: CGPoint, pixel: CGFloat = 0.5, color: Color, opacity: Double = 1) {
            self.pattern = pattern; self.center = center; self.pixel = pixel; self.color = color; self.opacity = opacity
        }
        /// Its extent in grid cells.
        public var bounds: CGRect {
            let width = CGFloat(pattern.map(\.count).max() ?? 0) * pixel, height = CGFloat(pattern.count) * pixel
            return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        }
    }

    /// The canvas every creature view draws on, in cells: room for hops, raised arms, the Z and sparkles.
    static let canvasCells = CGSize(width: 24, height: 19)
    /// Where the middle of the feet stands on that canvas, in cells: 7 cells of headroom (the stage hop's sparkles rise
    /// 6.3 cells above the head), 4 on each side (raised arms reach column 17, the Z 18.6, sparkles 18.8).
    static let canvasFeet = CGPoint(x: 12, y: 18)

    /// One cell in points, on whole device pixels (never below one): 2 points for 32, 3 for 48, 4 for 64.
    static func unit(size: CGFloat, displayScale: CGFloat) -> CGFloat {
        let scale = max(1, displayScale)
        return max(1, (size / CGFloat(columns) * scale).rounded(.down)) / scale
    }

    /// The cells a pose fills, in grid units, before the body transform.
    static func cells(for pose: Pose) -> [CGRect] { parts(for: pose).map(\.rect) }

    /// The eyes, in grid units, before the body transform. None at a height of 0 (the launch's gathering cloud).
    static func eyeRects(for pose: Pose) -> [CGRect] {
        guard pose.eyeHeight > 0 else { return [] }
        return eyes(for: .awake).map { eye in
            let bottom = pose.eyeBottom - CGFloat(pose.raise)
            return CGRect(x: CGFloat(eye.x + pose.look), y: bottom - pose.eyeHeight, width: 1, height: pose.eyeHeight)
        }
    }

    internal enum Part { case body, legTop, leg }
    internal struct PartRect { var rect: CGRect; var part: Part; var opacity: Double }

    /// The cells, each with what it belongs to: the body above the legs rises with the breath, the top leg row stretches.
    internal static func parts(for pose: Pose) -> [PartRect] {
        let legs = legColumns, top = legTop, last = rows - 1, arms = armColumns
        let raise = CGFloat(pose.raise)
        var out: [PartRect] = []
        for (i, p) in bodyPixels().enumerated() {
            var rect = CGRect(x: CGFloat(p.x), y: CGFloat(p.y), width: 1, height: 1)
            var part = Part.body
            if p.y >= top {
                guard let leg = legs.firstIndex(of: p.x) else { continue }
                if p.y == last, pose.legsTucked || (pose.liftedLegs.indices.contains(leg) && pose.liftedLegs[leg]) { continue }
                if p.y == top {
                    // The top leg row follows the body: taller when the body is up, gone when it is crouched below it.
                    rect = CGRect(x: rect.minX, y: CGFloat(top) - raise, width: 1, height: 1 + raise)
                    guard rect.height > 0 else { continue }
                    part = .legTop
                } else {
                    part = .leg
                }
            } else {
                if arms.contains(p.x), (p.x < columns / 2 ? pose.armLeft : pose.armRight) != .rest { continue }
                rect.origin.y -= raise
            }
            var opacity = 1.0
            if let states = pose.pixels, states.indices.contains(i) {
                let s = states[i]
                rect = CGRect(x: rect.minX + s.dx + (1 - s.scale) / 2, y: rect.minY + s.dy + (rect.height - rect.height * s.scale) / 2,
                              width: s.scale, height: rect.height * s.scale)
                opacity = s.opacity
            }
            out.append(PartRect(rect: rect, part: part, opacity: opacity))
        }
        for (arm, right) in [(pose.armRight, true), (pose.armLeft, false)] where arm != .rest {
            for p in arm.pixels {
                let x = right ? p.x : columns - 1 - p.x
                out.append(PartRect(rect: CGRect(x: CGFloat(x), y: CGFloat(p.y) - raise, width: 1, height: 1), part: .body, opacity: 1))
            }
        }
        return out
    }

    /// A drawn cell, in points, before the leap's lean (`Geometry.transform`).
    struct Cell: Equatable { var rect: CGRect; var opacity: Double }
    struct Geometry {
        var origin: CGPoint; var anchor: CGPoint; var body: [Cell]; var eyes: [CGRect]
        /// What is left to apply around `anchor` when drawing: the leap's lean with its squash and stretch, identity
        /// otherwise (a squash or a stretch alone is drawn in the cells themselves, on device pixels).
        var transform: CGAffineTransform = .identity
    }

    /// Where a pose's cells land for feet at `feet` (the middle of the feet's bottom edge, in points). Offsets and breath move
    /// by whole device pixels. With no rotation every edge lands on a device pixel, squashed or stretched too: each cell is
    /// scaled about the middle of the feet and its edges snapped, so the key poses of a hop stay as crisp as the rest pose
    /// (a transform would blur every edge and lose the eyes' one-pixel slit). The eyes keep one device pixel at least.
    static func geometry(for pose: Pose, feet: CGPoint, unit: CGFloat, displayScale: CGFloat) -> Geometry {
        let scale = max(1, displayScale)
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let leans = pose.rotation != 0
        var origin = CGPoint(x: feet.x - CGFloat(columns / 2) * unit + snap(pose.offset.dx * unit),
                             y: feet.y - CGFloat(rows) * unit + snap(pose.offset.dy * unit))
        if !leans { origin = CGPoint(x: snap(origin.x), y: snap(origin.y)) }
        let anchor = CGPoint(x: origin.x + CGFloat(columns / 2) * unit, y: origin.y + CGFloat(rows) * unit)
        let squash = !leans && (pose.scaleX != 1 || pose.scaleY != 1)
        /// A rectangle scaled about the feet, its edges on device pixels.
        func squashed(_ r: CGRect) -> CGRect {
            guard squash else { return r }
            let x0 = snap(anchor.x + (r.minX - anchor.x) * pose.scaleX), x1 = snap(anchor.x + (r.maxX - anchor.x) * pose.scaleX)
            let y0 = snap(anchor.y + (r.minY - anchor.y) * pose.scaleY), y1 = snap(anchor.y + (r.maxY - anchor.y) * pose.scaleY)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        let lift = CGFloat(pose.breath) / scale
        let body = parts(for: pose).map { part -> Cell in
            var rect = CGRect(x: origin.x + part.rect.minX * unit, y: origin.y + part.rect.minY * unit,
                              width: part.rect.width * unit, height: part.rect.height * unit)
            switch part.part {
            case .body: rect.origin.y -= lift
            case .legTop: rect.origin.y -= lift; rect.size.height += lift
            case .leg: break
            }
            return Cell(rect: squashed(rect), opacity: part.opacity)
        }
        let eyes = eyeRects(for: pose).map { r -> CGRect in
            let placed = squashed(CGRect(x: origin.x + r.minX * unit, y: origin.y + r.minY * unit - lift, width: unit, height: r.height * unit))
            let bottom = snap(placed.maxY)
            let top = min(snap(placed.minY), bottom - 1 / scale)
            return CGRect(x: placed.minX, y: top, width: placed.width, height: bottom - top)
        }
        var g = Geometry(origin: origin, anchor: anchor, body: body, eyes: eyes)
        if leans {
            g.transform = CGAffineTransform(translationX: anchor.x, y: anchor.y).rotated(by: pose.rotation * .pi / 180)
                .scaledBy(x: pose.scaleX, y: pose.scaleY).translatedBy(x: -anchor.x, y: -anchor.y)
        }
        return g
    }

    /// Draws a pose: the body as ONE path (rectangles filled one by one leave antialiasing seams), then the eyes, then the
    /// sprites, which live in the world: outside the squash, never following the offset.
    static func draw(_ context: inout GraphicsContext, pose: Pose, feet: CGPoint, unit: CGFloat, displayScale: CGFloat,
                     sprites: [Sprite] = []) {
        let g = geometry(for: pose, feet: feet, unit: unit, displayScale: displayScale)
        var ctx = context
        ctx.opacity *= pose.opacity
        if g.transform != .identity { ctx.concatenate(g.transform) }
        var body = Path()
        for cell in g.body {
            if cell.opacity >= 0.999 { body.addRect(cell.rect); continue }
            guard cell.opacity > 0.001 else { continue }
            var faded = ctx
            faded.opacity *= cell.opacity
            faded.fill(Path(cell.rect), with: .color(Theme.Colors.creature))
        }
        ctx.fill(body, with: .color(Theme.Colors.creature))
        var eyes = Path()
        for rect in g.eyes { eyes.addRect(rect) }
        ctx.fill(eyes, with: .color(Theme.Colors.creatureEye))

        let scale = max(1, displayScale)
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let world = CGPoint(x: feet.x - CGFloat(columns / 2) * unit, y: feet.y - CGFloat(rows) * unit)
        for sprite in sprites where sprite.opacity > 0.001 {
            let px = max(1 / scale, snap(sprite.pixel * unit))
            let x0 = snap(world.x + sprite.center.x * unit - CGFloat(sprite.pattern.map(\.count).max() ?? 0) * px / 2)
            let y0 = snap(world.y + sprite.center.y * unit - CGFloat(sprite.pattern.count) * px / 2)
            var path = Path()
            for (y, row) in sprite.pattern.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    path.addRect(CGRect(x: x0 + CGFloat(x) * px, y: y0 + CGFloat(y) * px, width: px, height: px))
                }
            }
            var sc = context
            sc.opacity *= sprite.opacity * pose.opacity
            sc.fill(path, with: .color(sprite.color))
        }
    }
}

/// The creature, alive: one Canvas in a timeline that wakes only when the frame changes (see `CreatureSchedule`).
/// Its layout is exactly the grid (16 by 11 cells); the canvas overflows it by 4 cells on each side and 7 above, so hops,
/// raised arms, the Z and sparkles are never clipped and never grow the row around it.
public struct CreatureView: View {
    public var state: CreatureState
    public var size: CGFloat
    public var profile: LifeProfile
    /// Stamps on the view's own clock (All set's hop 0.35 s after it appears).
    public var events: [CreatureStamp]
    /// The model's dated stamps (the sidebar), turned into stamps on the view's clock.
    public var moments: [CreatureMoment]
    /// An account is opening: the creature walks in place.
    public var walking: Bool
    /// When the clock starts; the view's appearance otherwise (the launch passes the moment its creature lands, so the
    /// first idle blink never doubles the landing's).
    public var clockStart: Date?
    public var seed: UInt64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.appearsActive) private var appearsActive
    /// When the view appeared: its clock's start unless it was given one.
    @State private var appeared: Date?
    @State private var asleepSince: Double?
    @State private var walk: CreatureWalk?

    public init(state: CreatureState, size: CGFloat = 32, profile: LifeProfile = .companion, events: [CreatureStamp] = [],
                moments: [CreatureMoment] = [], walking: Bool = false, clockStart: Date? = nil, seed: UInt64 = 7) {
        self.state = state; self.size = size; self.profile = profile; self.events = events; self.moments = moments
        self.walking = walking; self.clockStart = clockStart; self.seed = seed
    }

    public var body: some View {
        let unit = Creature.unit(size: size, displayScale: displayScale)
        let canvas = Creature.canvasCells, feet = Creature.canvasFeet
        let schedule = schedule(since: origin)
        TimelineView(schedule) { context in
            Canvas { ctx, _ in
                let frame = Self.drawnFrame(schedule, at: context.date, cadence: context.cadence)
                Creature.draw(&ctx, pose: frame.pose, feet: CGPoint(x: feet.x * unit, y: feet.y * unit), unit: unit,
                              displayScale: displayScale, sprites: frame.sprites)
            }
        }
        .frame(width: canvas.width * unit, height: canvas.height * unit)
        .padding(.top, -(feet.y - CGFloat(Creature.rows)) * unit)
        .padding(.bottom, -(canvas.height - feet.y) * unit)
        .padding(.horizontal, -(feet.x - CGFloat(Creature.columns / 2)) * unit)
        .frame(width: CGFloat(Creature.columns) * unit, height: CGFloat(Creature.rows) * unit)
        .allowsHitTesting(false)
        .onAppear {
            let now = Date()
            appeared = now
            let t = scene(now, since: Self.clockOrigin(clockStart: clockStart, appeared: now, now: now))
            asleepSince = state == .asleep ? max(0, t) : nil
            walk = walking ? CreatureWalk(start: max(0, t)) : nil
        }
        // Falling asleep starts the sleep loop's clock; waking keeps it, so the Z floating then fades with the wake.
        .onChange(of: state) { old, new in
            guard old != .asleep, new == .asleep else { return }
            asleepSince = scene(Date(), since: origin)
        }
        .onChange(of: walking) { _, now in
            let t = scene(Date(), since: origin)
            if now { walk = CreatureWalk(start: t) } else { walk?.end = t }
        }
    }

    /// What the Canvas draws at a timeline date: the schedule's frame at the timeline's cadence (see
    /// `CreatureSchedule.frame(at:cadence:)`).
    static func drawnFrame(_ schedule: CreatureSchedule, at date: Date, cadence: TimelineViewDefaultContext.Cadence) -> LifeFrame {
        schedule.frame(at: date, cadence: cadence)
    }

    /// The clock's start: the one given (the launch's landing) from the first frame it is known, else the appearance.
    static func clockOrigin(clockStart: Date?, appeared: Date?, now: Date) -> Date { clockStart ?? appeared ?? now }
    private var origin: Date { Self.clockOrigin(clockStart: clockStart, appeared: appeared, now: Date()) }

    private func scene(_ date: Date, since origin: Date) -> Double { date.timeIntervalSince(origin) / Theme.Motion.slow }

    private func schedule(since origin: Date) -> CreatureSchedule {
        CreatureSchedule(start: origin, mode: .init(capture: Theme.Motion.isCapture, reduceMotion: reduceMotion, active: appearsActive),
                         state: state, events: events + CreatureSchedule.stamps(moments, since: origin), profile: profile, seed: seed,
                         walking: walk, asleepSince: asleepSince)
    }
}
