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
