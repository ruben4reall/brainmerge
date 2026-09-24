import SwiftUI

/// The header of every screen: a serif title, an optional subtitle under it, and the screen's actions on the
/// right, aligned with the title line. One component, so the four screens line up the same way.
public struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Fonts.screenTitle)
                if let subtitle {
                    Text(subtitle).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            Spacer(minLength: 16)
            trailing.padding(.top, 5)
        }
    }
}

public extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title, subtitle: subtitle) { EmptyView() } }
}
