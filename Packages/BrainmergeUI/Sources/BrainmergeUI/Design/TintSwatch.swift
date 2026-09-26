import SwiftUI
import BrainmergeCore

/// A color to pick for an account. Chosen, its cream ring grows from nothing and the swatch pops 1, 1.08, 1 on the pop
/// spring; the ring of the one left shrinks away. With Reduce Motion the ring only fades.
struct TintSwatch: View {
    let tint: Tint
    let selected: Bool
    var size: CGFloat = 24
    var ring: CGFloat = 2.5
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pop's top.
    static let peak = 1.08

    var body: some View {
        Button(action: action) {
            Circle().fill(Theme.color(for: tint)).frame(width: size, height: size)
                .overlay(
                    SwatchRing(width: reduceMotion || selected ? ring : 0)
                        .fill(Theme.Colors.text, style: FillStyle(eoFill: true))
                        .opacity(!reduceMotion || selected ? 1 : 0)
                )
                .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.pop, value: selected)
                .keyframeAnimator(initialValue: 1.0, trigger: selected) { swatch, scale in
                    swatch.scaleEffect(scale)
                } keyframes: { _ in
                    // Deselected, or Reduce Motion: the same keyframes at rest, so nothing moves.
                    let top = selected && !reduceMotion ? Self.peak : 1
                    let slow = Theme.Motion.slow
                    KeyframeTrack {
                        CubicKeyframe(top, duration: 0.09 * slow)
                        SpringKeyframe(1, duration: 0.4 * slow, spring: Spring(response: 0.35 * slow, dampingRatio: 0.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tint.rawValue.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The ring inside a chosen swatch, as a band whose width animates from nothing.
struct SwatchRing: Shape {
    var width: CGFloat
    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = min(max(width, 0), rect.width / 2)
        // No band at all, not a hairline of two edges on top of each other.
        guard w > 0.05 else { return Path() }
        var path = Path(ellipseIn: rect)
        path.addEllipse(in: rect.insetBy(dx: w, dy: w))
        return path
    }
}

extension View {
    /// The stroke of a choice (a card, a notes app): the accent when chosen, faint otherwise, crossfading in 0.15 s.
    func choiceStroke(selected: Bool, radius: CGFloat = 12, reduceMotion: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.accent : Theme.Colors.surfaceLine, lineWidth: selected ? 2 : 1)
                .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: selected)
        )
    }
}
