import SwiftUI

/// The launch splash, shown while the first load runs: the creature walks in place on the window's background,
/// with its flat shadow. "Waking up…" appears only when the load is slow. With Reduce Motion the creature stands still.
/// VoiceOver reads one element: "Brainmerge is starting".
public struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var slow = false

    public init() {}

    public var body: some View {
        ZStack {
            WarmBackground(accents: [])
            GeometryReader { geo in
                let frame = Self.creatureFrame(in: geo.size)
                if reduceMotion {
                    creature(Creature.walkFrame(0), in: frame)
                } else {
                    TimelineView(.periodic(from: start, by: Theme.Launch.frameDuration)) { context in
                        let index = Creature.walkIndex(at: context.date, since: start, frameDuration: Theme.Launch.frameDuration, frozen: false)
                        creature(Creature.walkFrame(index), in: frame)
                    }
                }
                Text("Waking up…")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .position(x: frame.midX, y: frame.maxY + 24)
                    .opacity(slow ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brainmerge is starting")
        .task {
            try? await Task.sleep(for: .seconds(Theme.Launch.slowCaptionAfter))
            withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.Launch.fade)) { slow = true }
        }
    }

    /// Where the walk is drawn: centered, a little above the middle, on whole points so the pixel edges stay crisp.
    nonisolated static func creatureFrame(in size: CGSize) -> CGRect {
        let width = CGFloat(Creature.columns) * Theme.Launch.unit
        let height = CGFloat(Creature.walkRows) * Theme.Launch.unit
        let x = ((size.width - width) / 2).rounded(.down)
        let y = ((size.height - height) / 2 - Theme.Launch.lift).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// One frame: the shadow, then the body as a single path (rectangles filled one by one leave seams), then the eyes.
    private func creature(_ walk: Creature.WalkFrame, in frame: CGRect) -> some View {
        Canvas { context, _ in
            let unit = Theme.Launch.unit
            func cell(_ x: Int, _ y: Int, height: CGFloat = 1) -> CGRect {
                CGRect(x: frame.minX + CGFloat(x) * unit, y: frame.minY + CGFloat(y) * unit, width: unit, height: unit * height)
            }
            var shadow = Path()
            for p in walk.shadow { shadow.addRect(cell(p.x, p.y)) }
            context.fill(shadow, with: .color(Theme.Colors.selection))
            var body = Path()
            for p in walk.body { body.addRect(cell(p.x, p.y)) }
            context.fill(body, with: .color(Theme.Colors.creature))
            for e in walk.eyes { context.fill(Path(cell(e.x, e.y, height: e.height)), with: .color(Theme.Colors.creatureEye)) }
        }
    }
}
