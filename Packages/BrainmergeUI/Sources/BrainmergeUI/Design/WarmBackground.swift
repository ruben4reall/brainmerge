import SwiftUI

/// The canvas: dark and neutral, with a touch of purple at the top left. Nothing else: no halo competes with the accounts.
public struct WarmBackground: View {
    public init() {}

    public var body: some View {
        RadialGradient(colors: [Theme.Colors.backgroundTop, Theme.Colors.background, Theme.Colors.backgroundBottom],
                       center: .init(x: 0.15, y: 0), startRadius: 0, endRadius: 1100)
            .ignoresSafeArea()
    }
}
