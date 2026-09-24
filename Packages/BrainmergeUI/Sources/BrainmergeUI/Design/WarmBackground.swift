import SwiftUI
import BrainmergeCore

/// Dark, neutral background with a touch of purple at the top and subtle halos in the color of open accounts.
public struct WarmBackground: View {
    public var accents: [Tint]
    public init(accents: [Tint]) { self.accents = accents }

    public var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.Colors.backgroundTop, Theme.Colors.background, Theme.Colors.backgroundBottom],
                           center: .init(x: 0.15, y: 0), startRadius: 0, endRadius: 1100)
            if Theme.Halo.opacity > 0 { GeometryReader { geo in
                ForEach(Array(accents.prefix(3).enumerated()), id: \.offset) { index, tint in
                    Circle()
                        .fill(Theme.color(for: tint))
                        .frame(width: Theme.Halo.size, height: Theme.Halo.size)
                        .blur(radius: Theme.Halo.radius)
                        .opacity(Theme.Halo.opacity)
                        .position(x: geo.size.width * [0.05, 0.9, 0.5][index], y: geo.size.height * [0.05, 0.3, 1.1][index])
                }
            } }
        }
        .ignoresSafeArea()
    }
}
