import SwiftUI

/// The launch splash, shown while the first load runs: the creature walks in place on the window's background,
/// with its flat shadow. "Waking up…" appears only when the load is slow. With Reduce Motion the creature stands still.
/// VoiceOver reads one element: "Brainmerge is starting".
public struct LaunchView: View {
    /// Said to VoiceOver when the splash hands over: its only element goes away and the accounts appear.
    static let readyAnnouncement = "Brainmerge is ready"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date()
    @State private var slow = false

    public init() {}

    public var body: some View {
        ZStack {
            WarmBackground(accents: [])
            GeometryReader { geo in
                let frame = Self.creatureFrame(in: geo.size)
                if reduceMotion {
                    creature(0, in: frame)
                } else {
                    TimelineView(.periodic(from: start, by: Theme.Launch.frameDuration)) { context in
                        creature(Creature.walkIndex(at: context.date, since: start, frameDuration: Theme.Launch.frameDuration, frozen: false), in: frame)
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

    /// One frame of the walk: the flat shadow on the row under the feet, then the creature (Creature.draw).
    private func creature(_ index: Int, in frame: CGRect) -> some View {
        Canvas { context, _ in
            let unit = Theme.Launch.unit
            let ground = frame.minY + CGFloat(Creature.walkRows - 1) * unit
            let shadow = Creature.walkShadow(index)
            context.fill(Path(CGRect(x: frame.minX + CGFloat(shadow.lowerBound) * unit, y: ground,
                                     width: CGFloat(shadow.count) * unit, height: unit)), with: .color(Theme.Colors.selection))
            var ctx = context
            Creature.draw(&ctx, pose: Creature.walkFrame(index), feet: CGPoint(x: frame.midX, y: ground), unit: unit, displayScale: displayScale)
        }
    }
}
