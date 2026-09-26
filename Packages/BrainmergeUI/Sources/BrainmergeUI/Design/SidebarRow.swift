import SwiftUI

extension EnvironmentValues {
    /// True while the pointer is over the sidebar row that holds this view (set by `SidebarRowStyle`).
    @Entry var sidebarRowHovered = false
}

/// A row of the sidebar, a screen or an account. The whole row is the click target, not only its text and icon.
/// Under the pointer it gets a faint cream fill, a slightly stronger one while pressed, and the purple selection
/// when it is the current screen: hover stays neutral so the purple keeps meaning "selected" (DESIGN.md).
/// The hover state lives in the row, so moving the pointer redraws one row, not the window.
struct SidebarRowStyle: ButtonStyle {
    var selected = false

    /// A disabled row (an account opening or being updated) looks inactive instead of silently ignoring clicks.
    static let disabledOpacity = 0.75

    /// The fill's change: a press shows at once (it answers the click), its release, the hover and the selection take
    /// 0.12 s. Nothing with Reduce Motion: a color that follows the pointer needs no fade.
    nonisolated static func fillAnimation(pressed: Bool, reduceMotion: Bool) -> Animation? {
        pressed || reduceMotion ? nil : Theme.Motion.out(Theme.Motion.hover)
    }

    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration, selected: selected) }

    struct Row: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var fill: Color {
            if selected { return Theme.Colors.selection }
            if configuration.isPressed { return Theme.Colors.rowPressed }
            if hovering { return Theme.Colors.rowHover }
            return .clear
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
            configuration.label
                .environment(\.sidebarRowHovered, hovering)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(shape)
                .background { shape.fill(fill).animation(SidebarRowStyle.fillAnimation(pressed: configuration.isPressed, reduceMotion: reduceMotion), value: fill) }
                .opacity(isEnabled ? 1 : SidebarRowStyle.disabledOpacity)
                .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: isEnabled)
                // Screenshots never show a stray highlight where the pointer happens to rest.
                .onHover { inside in hovering = inside && isEnabled && !Theme.Motion.isCapture }
                // A click hands the focus to Claude: the exit event may never come, so the highlight goes with the click.
                .onChange(of: configuration.isPressed) { wasPressed, pressed in if wasPressed, !pressed { hovering = false } }
                .onChange(of: isEnabled) { _, enabled in if !enabled { hovering = false } }
        }
    }
}

/// The word at the end of an account row ("Open", "Show"): readable at rest, so a click's effect is never a guess,
/// and full cream under the pointer, in step with the row's fill. It never truncates: the account's name gives way first.
/// A new word ("Opening…" to "Show") crossfades.
struct SidebarRowHint: View {
    static let resting = Theme.Colors.textMuted
    static let pointed = Theme.Colors.text
    let text: String
    @Environment(\.sidebarRowHovered) private var hovered
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(hovered ? Self.pointed : Self.resting)
            .animation(reduceMotion ? nil : Theme.Motion.out(Theme.Motion.hover), value: hovered)
            .contentTransition(.opacity)
            .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: text)
            .fixedSize()
    }
}
