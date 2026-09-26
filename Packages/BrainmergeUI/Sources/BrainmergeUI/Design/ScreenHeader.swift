import SwiftUI

/// The header of every screen: a serif title, an optional subtitle under it, and the screen's actions on the
/// right, aligned with the title line. One component, so the four screens line up the same way.
/// A subtitle that says work is running gets a small spinner before it; a new subtitle crossfades over the old one.
public struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let busy: Bool
    /// What a crossfade follows: the subtitle, or only its words when a figure in it moves every few seconds.
    let changeKey: String?
    let trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ title: String, subtitle: String? = nil, busy: Bool = false, changeKey: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.busy = busy; self.changeKey = changeKey; self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Fonts.screenTitle)
                if let subtitle {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.small).transition(.opacity) }
                        Text(subtitle).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: changeKey ?? subtitle)
                    .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: busy)
                }
            }
            Spacer(minLength: 16)
            trailing.padding(.top, 5)
        }
    }
}

public extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title, subtitle: subtitle, busy: false) { EmptyView() } }
}
