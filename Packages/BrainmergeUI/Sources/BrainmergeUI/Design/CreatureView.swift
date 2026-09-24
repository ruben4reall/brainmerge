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
    public struct Pixel: Equatable, Sendable { public let x: Int; public let y: Int; public init(x: Int, y: Int) { self.x = x; self.y = y } }
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
