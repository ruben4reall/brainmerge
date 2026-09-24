import SwiftUI

/// A system glass card (20 px corners) with a cream highlight on the top-left edge.
public struct GlassCard<Content: View>: View {
    var radius: CGFloat
    var content: Content
    public init(radius: CGFloat = 12, @ViewBuilder content: () -> Content) { self.radius = radius; self.content = content() }
    public var body: some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Colors.surfaceLine, lineWidth: 1)
            )
    }
}

/// The primary action button: flat, the accent color, nothing else.
public struct AccentPillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
public extension ButtonStyle where Self == AccentPillButtonStyle {
    static var accentPill: AccentPillButtonStyle { AccentPillButtonStyle() }
}
