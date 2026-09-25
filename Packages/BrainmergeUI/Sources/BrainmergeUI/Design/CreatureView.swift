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

    // MARK: The walk of the launch splash, computed from the grid above: a new grid walks without new drawings.

    /// The frames of one step: contact, first legs lifted, contact, the other legs lifted.
    public static let walkCycle = 4
    /// The walk's height: the grid, one row of headroom above (the body bobs up) and one row of shadow below.
    public static let walkRows = rows + 2

    /// One frame of the walk: the purple body and legs, the eyes, and the flat shadow under the feet.
    public struct WalkFrame: Equatable, Sendable {
        public let body: [Pixel]
        public let eyes: [Eye]
        public let shadow: [Pixel]
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
    private static func filled(_ row: String) -> [Int] { row.enumerated().compactMap { $1 == "X" ? $0 : nil } }

    /// Frame `index` of the walk, any integer (it loops). On contact (even frames) the still creature stands one row lower,
    /// every foot on the ground; on the passing frames the body is up one row, half the legs stay planted and stretch
    /// to the ground, the other half are lifted one row, alternating, and the shadow narrows by one column on each side.
    public static func walkFrame(_ index: Int) -> WalkFrame {
        let phase = ((index % walkCycle) + walkCycle) % walkCycle
        let contact = phase % 2 == 0
        let drop = contact ? 1 : 0
        let top = legTop, ground = rows, legs = legColumns
        var pixels = bodyPixels().filter { $0.y < top }.map { Pixel(x: $0.x, y: $0.y + drop) }
        for (i, x) in legs.enumerated() {
            let lifted = !contact && (i % 2 == 0) == (phase == 1)
            let bottom = lifted ? ground - 1 : ground
            pixels += (top + drop...bottom).map { Pixel(x: x, y: $0) }
        }
        let eyes = eyes(for: .awake).map { Eye(x: $0.x, y: $0.y + drop, height: $0.height) }
        guard let left = legs.min(), let right = legs.max() else { return WalkFrame(body: pixels, eyes: eyes, shadow: []) }
        let inset = contact ? 0 : 1
        let shadow = (left + inset...max(left + inset, right - inset)).map { Pixel(x: $0, y: ground + 1) }
        return WalkFrame(body: pixels, eyes: eyes, shadow: shadow)
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

public struct CreatureView: View {
    public var state: CreatureState
    public var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(state: CreatureState, size: CGFloat = 46) { self.state = state; self.size = size }

    public var body: some View {
        let unit = size / CGFloat(Creature.columns)
        let height = unit * CGFloat(Creature.rows)
        ZStack {
            if state != .asleep, Theme.Creature.glowOpacity > 0 {
                Circle().fill(Theme.Colors.creature.opacity(Theme.Creature.glowOpacity)).frame(width: size * 1.3, height: size * 1.3).blur(radius: size * 0.2)
            }
            if state == .glowing {
                AuraView(state: .full, cornerRadius: size * 0.3).frame(width: size * 1.35, height: height * 1.5)
            }
            Canvas { context, _ in
                // A single path for the whole body: filling rectangles one by one leaves antialiasing seams.
                var body = Path()
                for p in Creature.bodyPixels() {
                    body.addRect(CGRect(x: CGFloat(p.x) * unit, y: CGFloat(p.y) * unit, width: unit, height: unit))
                }
                context.fill(body, with: .color(Theme.Colors.creature))
                for e in Creature.eyes(for: state) {
                    context.fill(Path(CGRect(x: CGFloat(e.x) * unit, y: CGFloat(e.y) * unit, width: unit, height: unit * e.height)), with: .color(Theme.Colors.creatureEye))
                }
            }
            .frame(width: size, height: height)
        }
        .frame(width: size * 1.4, height: height * 1.5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state)
    }
}
