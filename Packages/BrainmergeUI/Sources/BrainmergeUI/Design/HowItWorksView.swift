import SwiftUI
import BrainmergeCore

/// The onboarding illustration: several accounts on the left, one memory in the middle, and notes flowing
/// along the lines. The flow animates gently; with Reduce Motion the dots stand still.
public struct HowItWorksView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    struct Lane { let name: String; let tint: Tint }
    let lanes = [Lane(name: "Personal", tint: .orange), Lane(name: "Work", tint: .blue), Lane(name: "Client", tint: .purple)]

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.35 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            Canvas { canvas, size in
                let leftX = size.width * 0.16, midX = size.width * 0.56, rightX = size.width * 0.92
                let centerY = size.height / 2
                let laneYs = [size.height * 0.2, centerY, size.height * 0.8]
                // Lines from each account to the memory, and from the memory to Claude Code.
                for y in laneYs {
                    var path = Path()
                    path.move(to: CGPoint(x: leftX + 30, y: y))
                    path.addCurve(to: CGPoint(x: midX - 34, y: centerY), control1: CGPoint(x: leftX + 120, y: y), control2: CGPoint(x: midX - 120, y: centerY))
                    canvas.stroke(path, with: .color(Theme.Colors.surfaceLine), lineWidth: 1.5)
                }
                var out = Path(); out.move(to: CGPoint(x: midX + 34, y: centerY)); out.addLine(to: CGPoint(x: rightX - 22, y: centerY))
                canvas.stroke(out, with: .color(Theme.Colors.surfaceLine), lineWidth: 1.5)
                // Dots travelling toward the memory (notes being saved), then out (notes being read).
                for (index, y) in laneYs.enumerated() {
                    let phase = (t + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                    let p = Self.point(on: CGPoint(x: leftX + 30, y: y), CGPoint(x: leftX + 120, y: y), CGPoint(x: midX - 120, y: centerY), CGPoint(x: midX - 34, y: centerY), at: phase)
                    canvas.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Theme.color(for: lanes[index].tint)))
                }
                let outPhase = (t + 0.5).truncatingRemainder(dividingBy: 1)
                let ox = midX + 34 + (rightX - 22 - midX - 34) * outPhase
                canvas.fill(Path(ellipseIn: CGRect(x: ox - 3, y: centerY - 3, width: 6, height: 6)), with: .color(Theme.Colors.accent))
                // The memory: a rounded square with the creature's color, the accounts, and Claude Code.
                let box = CGRect(x: midX - 34, y: centerY - 34, width: 68, height: 68)
                canvas.fill(Path(roundedRect: box, cornerRadius: 14), with: .color(Theme.Colors.selection))
                canvas.stroke(Path(roundedRect: box, cornerRadius: 14), with: .color(Theme.Colors.accent), lineWidth: 1.5)
                canvas.draw(Text("Memory").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Colors.text), at: CGPoint(x: midX, y: centerY))
                for (index, y) in laneYs.enumerated() {
                    let lane = lanes[index]
                    canvas.fill(Path(ellipseIn: CGRect(x: leftX - 14, y: y - 14, width: 28, height: 28)), with: .color(Theme.color(for: lane.tint).opacity(0.9)))
                    canvas.draw(Text(String(lane.name.prefix(1))).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: leftX, y: y))
                    canvas.draw(Text(lane.name).font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted), at: CGPoint(x: leftX, y: y + 24))
                }
                canvas.draw(Text("Claude Code").font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted), at: CGPoint(x: rightX - 10, y: centerY + 22))
                canvas.draw(Text("reads and writes").font(.system(size: 10)).foregroundStyle(Theme.Colors.textFaint), at: CGPoint(x: rightX - 10, y: centerY + 36))
                canvas.fill(Path(ellipseIn: CGRect(x: rightX - 22, y: centerY - 12, width: 24, height: 24)), with: .color(Theme.Colors.surfaceLine))
                canvas.draw(Text(">_").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.Colors.text), at: CGPoint(x: rightX - 10, y: centerY))
            }
        }
        .accessibilityLabel("Three accounts write into one memory folder that Claude Code reads and writes in every account.")
    }

    /// A point on a cubic Bezier curve.
    static func point(on p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, at t: Double) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        return CGPoint(x: x, y: y)
    }
}
