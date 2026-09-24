import SwiftUI

public enum AuraState: Equatable, Sendable { case off, soft, full }

public enum Aura {
    /// The aura's angle at a given moment: one full turn per period; frozen when animations are reduced.
    public static func angle(at date: Date, period: TimeInterval, frozen: Bool) -> Angle {
        if frozen { return .degrees(0) }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return .degrees(t / period * 360)
    }
}

/// The Siri-style aura: a conic gradient that rotates around a rounded, blurred rectangle, plus a crisp thin outline.
public struct AuraView: View {
    public var state: AuraState
    public var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AuraState, cornerRadius: CGFloat = 26) { self.state = state; self.cornerRadius = cornerRadius }

    public var body: some View {
        if state == .off {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let angle = Aura.angle(at: context.date, period: Theme.Aura.period, frozen: reduceMotion)
                let gradient = AngularGradient(colors: Theme.auraColors + [Theme.auraColors[0]], center: .center, angle: angle)
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius + 6, style: .continuous)
                        .strokeBorder(gradient, lineWidth: Theme.Aura.lineWidth)
                        .blur(radius: state == .full ? 16 : 24)
                        .opacity(state == .full ? Theme.Aura.fullOpacity : Theme.Aura.softOpacity)
                    RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                        .strokeBorder(gradient, lineWidth: 1.5)
                        .opacity(state == .full ? 0.8 : 0.25)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
