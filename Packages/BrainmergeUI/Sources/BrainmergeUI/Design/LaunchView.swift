import SwiftUI

/// The launch splash, an overlay on the window until its creature has landed: the pixels gather into the creature, the
/// wordmark rises, and once the app is ready the creature leaps into the sidebar while the screens fade in underneath
/// (LaunchScene.swift). A click or any key hurries it once the app is ready. It draws the frames of a `LaunchClock` and
/// nothing else; the same overlay draws the leap that ends the guided setup. VoiceOver reads one element:
/// "Brainmerge is starting".
public struct LaunchView: View {
    /// Said to VoiceOver when the splash hands over: its only element goes away and the accounts appear.
    static let readyAnnouncement = "Brainmerge is ready"

    let clock: LaunchClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    public init(clock: LaunchClock) { self.clock = clock }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: clock.finished)) { context in
                let frame = clock.frame(at: context.date, size: geo.size)
                splash(frame, size: geo.size)
                    .onChange(of: frame.finished, initial: true) { _, done in if done { clock.finish() } }
            }
        }
        .onAppear { clock.begin(at: Date(), reduceMotion: reduceMotion) }
    }

    private func splash(_ frame: LaunchFrame, size: CGSize) -> some View {
        let launching = clock.mode == .launch
        let listening = launching && !frame.handingOff
        return LaunchPicture(frame: frame, size: size, words: launching)
            .contentShape(Rectangle())
            .onTapGesture { clock.skip(at: Date()) }
            .focusable(listening)
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress { press in
                clock.skip(at: Date())
                return press.modifiers.contains(.command) ? .ignored : .handled   // menu shortcuts (Quit) still work
            }
            .onAppear { focused = listening }
            // From the hand-off on, clicks go through to the screens underneath.
            .allowsHitTesting(listening)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brainmerge is starting")
            .accessibilityHidden(!listening)
    }
}

/// One frame of the overlay, drawn: the ground shadow and the creature in one Canvas, the wordmark and "Waking up…" under
/// them (the launch only). Transparent everywhere else: the screens show through.
struct LaunchPicture: View {
    var frame: LaunchFrame
    var size: CGSize
    var words: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let feet = AssembleScene.splashFeet(in: size)
        ZStack {
            Canvas { context, _ in
                if frame.shadowOpacity > 0.001 {
                    var shadow = context
                    shadow.opacity = frame.shadowOpacity
                    shadow.fill(Path(AssembleScene.shadowRect(feet: feet, inset: frame.shadowInset)), with: .color(Theme.Colors.selection))
                }
                var ctx = context
                Creature.draw(&ctx, pose: frame.pose, feet: frame.feet, unit: frame.unit, displayScale: displayScale)
            }
            if words {
                Text("Brainmerge")
                    .font(Theme.Fonts.screenTitle)
                    .foregroundStyle(Theme.Colors.text)
                    .blur(radius: frame.wordmarkBlur)
                    .opacity(frame.wordmarkOpacity)
                    .position(x: feet.x, y: feet.y + AssembleScene.unit + 30 + frame.wordmarkRise)
                Text("Waking up…")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .opacity(frame.captionOpacity)
                    .position(x: feet.x, y: feet.y + AssembleScene.unit + 64)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
