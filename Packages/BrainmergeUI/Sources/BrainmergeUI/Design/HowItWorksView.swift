import SwiftUI

/// How it works, step two of the guided setup: HowItWorksScene played on its own clock, one Canvas at the display's
/// rate. Every visit starts with Personal; Reduce Motion and captures show the scene's still and never tick.
public struct HowItWorksView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var texts = HowItWorksTexts()
    public init() {}

    /// The page slides in first (a 0.4 s spring): the story starts once it has settled, so its first beat is seen whole.
    static let leadIn: TimeInterval = 0.3

    public var body: some View {
        let frozen = reduceMotion || Theme.Motion.isCapture
        TimelineView(.animation(paused: frozen)) { context in
            HowItWorksCanvas(frame: Self.sceneFrame(elapsed: context.date.timeIntervalSince(start), frozen: frozen), texts: texts)
        }
        .frame(width: HowItWorksScene.size.width, height: HowItWorksScene.size.height)
        .onAppear { start = Date().addingTimeInterval(Self.leadIn * Theme.Motion.slow) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three accounts, each in its own window. One account's Claude Code saves a note into the memory, a folder on this Mac, and the other accounts can read the same note.")
        .accessibilityAddTraits(.isImage)
    }

    /// The frame shown `elapsed` seconds after the story started: the still when frozen, the first frame until it starts.
    static func sceneFrame(elapsed: TimeInterval, frozen: Bool) -> HowItWorksScene.Frame {
        frozen ? HowItWorksScene.still() : HowItWorksScene.frame(at: max(0, elapsed) / Theme.Motion.slow)
    }
}

/// The names, labels and captions of the scene, laid out once per display scale and drawn from here on every frame.
@MainActor final class HowItWorksTexts {
    enum Style: Hashable { case caption, name, title, subtitle, prompt }
    struct Laid { let text: GraphicsContext.ResolvedText; let size: CGSize }
    private struct Key: Hashable { let string: String; let style: Style }
    private var laid: [Key: Laid] = [:]
    private var scale: CGFloat = 0
    /// How many texts went through layout (tests: each string once).
    private(set) var resolutions = 0

    func text(_ string: String, _ style: Style, in ctx: GraphicsContext) -> Laid {
        let scale = ctx.environment.displayScale
        if scale != self.scale { laid = [:]; self.scale = scale }
        let key = Key(string: string, style: style)
        if let known = laid[key] { return known }
        let resolved = ctx.resolve(Self.text(string, style))
        let result = Laid(text: resolved, size: resolved.measure(in: CGSize(width: HowItWorksScene.size.width, height: 40)))
        laid[key] = result
        resolutions += 1
        return result
    }

    static func text(_ string: String, _ style: Style) -> Text {
        switch style {
        case .caption: Text(string).font(.system(size: HowItWorksScene.captionFontSize)).foregroundStyle(Theme.Colors.textMuted)
        case .name: Text(string).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Colors.text.opacity(0.85))
        case .title: Text(string).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.Colors.text)
        case .subtitle: Text(string).font(.system(size: 10.5)).foregroundStyle(Theme.Colors.textMuted)
        case .prompt: Text(string).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.Colors.textFaint)
        }
    }
}

/// Draws one frame of How it works, 1:1 in a 520 by 224 point canvas.
struct HowItWorksCanvas: View {
    typealias S = HowItWorksScene
    var frame: S.Frame
    var texts: HowItWorksTexts

    var body: some View {
        Canvas { ctx, _ in Self.draw(frame, in: &ctx, texts: texts) }
            .frame(width: S.size.width, height: S.size.height)
    }

    static func tint(_ account: Int) -> Color { Theme.color(for: S.accounts[account].tint) }

    static func draw(_ frame: S.Frame, in ctx: inout GraphicsContext, texts: HowItWorksTexts) {
        // The lanes at rest, dashed, from under each window to the folder.
        for lane in restLanes {
            ctx.stroke(lane, with: .color(Theme.Colors.graphLink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 4]))
        }
        // The lanes a note is lighting, in its writer's tint.
        for trail in frame.trails where trail.opacity > 0.01 {
            ctx.stroke(polyline(S.lanes[trail.lane].segment(from: trail.from, to: trail.to)),
                       with: .color(tint(trail.source).opacity(trail.opacity)), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        }
        for i in S.accounts.indices { drawWindow(i, frame.windows[i], in: ctx, texts: texts) }
        drawFolder(frame, in: ctx, texts: texts)
        for chip in frame.chips where !chip.behindFront { drawChip(chip, in: ctx) }

        // The creature on its flat shadow, which narrows and lightens while it is in the air.
        let air = S.air(of: frame.creature)
        ctx.fill(Path(roundedRect: S.shadowRect(air: air), cornerRadius: 1.5),
                 with: .color(Theme.Colors.selection.opacity(S.shadowOpacity(air: air))))
        Creature.draw(&ctx, pose: frame.creature, feet: S.creatureFeet, unit: S.creatureUnit, displayScale: ctx.environment.displayScale)

        if frame.captionOpacity > 0.01 {
            var caption = ctx
            caption.opacity = frame.captionOpacity
            caption.draw(texts.text(frame.caption, .caption, in: ctx).text,
                         at: CGPoint(x: S.captionCenter.x, y: S.captionCenter.y + frame.captionRise))
        }
    }

    /// The shapes that never move, built once: the visible part of each lane, the folder's back with its tab.
    static let restLanes: [Path] = S.lanes.indices.map { polyline(S.lanes[$0].segment(from: S.laneVisibleStart[$0], to: 1)) }
    static let folderBack: Path = {
        let fr = S.folderRect
        let tab = Path(roundedRect: CGRect(x: fr.minX, y: fr.minY - 7, width: 38, height: 14), cornerRadius: 4, style: .continuous)
        return Path(roundedRect: fr, cornerRadius: 7, style: .continuous).union(tab)
    }()

    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    /// An account's window: title bar with its lights, dot and name; Claude Code's prompt; the last note it received.
    static func drawWindow(_ i: Int, _ state: S.WindowState, in ctx: GraphicsContext, texts: HowItWorksTexts) {
        let r = S.windowRect(i)
        let shape = Path(roundedRect: r, cornerRadius: 9, style: .continuous)
        ctx.fill(shape, with: .color(Theme.Colors.background))
        ctx.fill(shape, with: .color(Theme.Diagram.windowGlass))
        ctx.stroke(shape, with: .color(Theme.Colors.surfaceLine), lineWidth: 1)
        if state.outline > 0.01, let lit = state.outlineSource {
            ctx.stroke(shape, with: .color(tint(lit).opacity(0.9 * state.outline)), lineWidth: 1.5)
        }
        if let ring = state.ring, let source = state.ringSource {
            let e = Ease.out(ring)
            let grown = r.insetBy(dx: -6 * e, dy: -6 * e)
            ctx.stroke(Path(roundedRect: grown, cornerRadius: 9 + 6 * e, style: .continuous),
                       with: .color(tint(source).opacity(0.55 * (1 - e))), lineWidth: 1.5)
        }
        for k in 0..<3 {
            ctx.fill(Path(ellipseIn: CGRect(x: r.minX + 9 + CGFloat(k) * 9, y: r.minY + 7, width: 6, height: 6)), with: .color(Theme.Diagram.windowLight))
        }
        let name = texts.text(S.accounts[i].name, .name, in: ctx)
        let nameX = r.midX + 6
        ctx.fill(Path(ellipseIn: CGRect(x: nameX - name.size.width / 2 - 12, y: r.minY + 6.5, width: 7, height: 7)), with: .color(tint(i)))
        ctx.draw(name.text, at: CGPoint(x: nameX, y: r.minY + 10))
        ctx.fill(Path(CGRect(x: r.minX, y: r.minY + 20, width: r.width, height: 1)), with: .color(Theme.Colors.surfaceLine.opacity(0.7)))

        // Claude Code's prompt, typing a note in the account's tint.
        let rowY = r.minY + 33
        ctx.draw(texts.text(">_", .prompt, in: ctx).text, at: CGPoint(x: r.minX + 10, y: rowY), anchor: .leading)
        let widths: [CGFloat] = [10, 6, 14, 8, 12, 9]
        var x = r.minX + 28
        var typed = ctx
        typed.opacity = state.typedOpacity
        for k in 0..<state.typed {
            typed.fill(Path(roundedRect: CGRect(x: x, y: rowY - 2.5, width: widths[k], height: 5), cornerRadius: 1), with: .color(tint(i).opacity(0.9)))
            x += widths[k] + 3
        }
        if state.cursor { ctx.fill(Path(CGRect(x: x, y: rowY - 4, width: 5, height: 8)), with: .color(Theme.Colors.text.opacity(0.7))) }

        // The last note it received from another account: a page in that account's tint and three lines.
        func noteRow(_ source: Int, opacity: Double, rise: Double) {
            guard opacity > 0.01 else { return }
            var row = ctx
            row.opacity = opacity
            let y = r.minY + 50 + rise
            row.fill(Path(roundedRect: CGRect(x: r.minX + 10, y: y - 5, width: 8, height: 10), cornerRadius: 1.5), with: .color(tint(source)))
            let lengths: [CGFloat] = source == 0 ? [18, 10, 22] : source == 1 ? [12, 20, 14] : [22, 8, 16]
            var bx = r.minX + 26
            for w in lengths {
                row.fill(Path(roundedRect: CGRect(x: bx, y: y - 2, width: w, height: 4), cornerRadius: 1), with: .color(Theme.Colors.text.opacity(0.32)))
                bx += w + 3
            }
        }
        if let previous = state.previous { noteRow(previous, opacity: state.previousOpacity, rise: 0) }
        if let received = state.received { noteRow(received, opacity: state.receivedOpacity, rise: state.receivedRise) }
    }

    /// The memory: a folder on this Mac, two notes standing in it, the landing note between its back and its front.
    static func drawFolder(_ frame: S.Frame, in ctx: GraphicsContext, texts: HowItWorksTexts) {
        let fr = S.folderRect
        let back = folderBack
        ctx.fill(back, with: .color(Theme.Colors.background))
        ctx.fill(back, with: .color(Theme.Colors.accentDeep.opacity(0.2)))
        ctx.stroke(back, with: .color(Theme.Colors.accent.opacity(0.55)), lineWidth: 1)
        var behind = ctx
        behind.translateBy(x: fr.minX + 52, y: fr.minY + 22)
        behind.rotate(by: .degrees(-3))
        behind.fill(Path(roundedRect: CGRect(x: -38, y: -18, width: 76, height: 40), cornerRadius: 2), with: .color(Theme.Colors.text.opacity(0.78)))
        var front = ctx
        front.translateBy(x: fr.minX + 54, y: fr.minY + 24)
        front.rotate(by: .degrees(2))
        front.fill(Path(roundedRect: CGRect(x: -36, y: -16, width: 72, height: 40), cornerRadius: 2), with: .color(Theme.Colors.text))
        for (k, w) in [44.0, 30.0].enumerated() {
            front.fill(Path(CGRect(x: -28, y: -11 + CGFloat(k) * 4, width: w, height: 1.2)), with: .color(Theme.Diagram.noteLine))
        }
        for chip in frame.chips where chip.behindFront { drawChip(chip, in: ctx) }

        let frontHeight = (fr.maxY - S.folderFrontTop) * (1 - frame.frontSquash)
        let panel = CGRect(x: fr.minX - 3, y: fr.maxY - frontHeight, width: fr.width + 6, height: frontHeight)
        let panelPath = Path(roundedRect: panel, cornerRadius: 7, style: .continuous)
        ctx.fill(panelPath, with: .color(Theme.Colors.background))
        ctx.fill(panelPath, with: .linearGradient(Gradient(colors: [Theme.Colors.accentDeep.opacity(0.42), Theme.Colors.accentDeep.opacity(0.3)]),
                                                  startPoint: CGPoint(x: 0, y: panel.minY), endPoint: CGPoint(x: 0, y: panel.maxY)))
        ctx.fill(Path(CGRect(x: panel.minX + 6, y: panel.minY + 1, width: panel.width - 12, height: 1)), with: .color(Theme.Diagram.folderEdge))
        ctx.stroke(panelPath, with: .color(Theme.Colors.accent), lineWidth: 1.25)
        if frame.folderFlash > 0.01 { ctx.stroke(panelPath, with: .color(Theme.Colors.accentLight.opacity(frame.folderFlash)), lineWidth: 2) }
        ctx.draw(texts.text("Memory", .title, in: ctx).text, at: CGPoint(x: panel.midX, y: panel.midY - 6))
        ctx.draw(texts.text("on this Mac", .subtitle, in: ctx).text, at: CGPoint(x: panel.midX, y: panel.midY + 9))
    }

    /// A note page in flight, 13 by 16 points, its corner folded.
    static func drawChip(_ chip: S.Chip, in ctx: GraphicsContext) {
        guard chip.opacity > 0.01 else { return }
        var g = ctx
        g.opacity = chip.opacity
        g.translateBy(x: chip.position.x, y: chip.position.y)
        g.rotate(by: .degrees(chip.rotation))
        g.scaleBy(x: chip.scale, y: chip.scale)
        let w: CGFloat = 13, h: CGFloat = 16, fold: CGFloat = 4
        var page = Path()
        page.move(to: CGPoint(x: -w / 2, y: -h / 2))
        page.addLine(to: CGPoint(x: w / 2 - fold, y: -h / 2))
        page.addLine(to: CGPoint(x: w / 2, y: -h / 2 + fold))
        page.addLine(to: CGPoint(x: w / 2, y: h / 2))
        page.addLine(to: CGPoint(x: -w / 2, y: h / 2))
        page.closeSubpath()
        g.fill(page, with: .color(tint(chip.source)))
        var corner = Path()
        corner.move(to: CGPoint(x: w / 2 - fold, y: -h / 2))
        corner.addLine(to: CGPoint(x: w / 2 - fold, y: -h / 2 + fold))
        corner.addLine(to: CGPoint(x: w / 2, y: -h / 2 + fold))
        corner.closeSubpath()
        g.fill(corner, with: .color(Theme.Diagram.pageFold))
        for (i, length) in [7.0, 5.0, 6.0].enumerated() {
            g.fill(Path(CGRect(x: -w / 2 + 3, y: -h / 2 + 5 + CGFloat(i) * 3, width: length, height: 1.2)), with: .color(Theme.Diagram.pageLine))
        }
    }
}
