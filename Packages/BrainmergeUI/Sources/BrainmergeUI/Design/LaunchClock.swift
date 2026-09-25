import SwiftUI

/// The one clock of a hand-off: the splash overlay draws its frames, the screens underneath read their opacity from the
/// same frames, and the creature it lands on stays hidden until the overlay goes. One clock, never two animations.
///
/// Two scenes run on it: the launch (`AssembleScene`), then, on a first run, the end of the guided setup (`GuideExit`).
/// Times are seconds on the scene's clock since `start`, slowed by `BRAINMERGE_SLOW_MOTION` in debug builds.
@MainActor @Observable
public final class LaunchClock {
    /// The window's coordinate space: the overlay draws in it, the target creatures measure themselves in it.
    public nonisolated static let space = "window"

    public enum Mode: Equatable, Sendable {
        case launch
        /// "Open Brainmerge": the All set creature leaps from `source` (nil when out of sight, or with Reduce Motion).
        case exit(source: LaunchTarget?)
    }
    /// Who reads the clock underneath the overlay: the main window's screens, or the guided setup.
    public enum Role: Sendable { case main, guide }

    public private(set) var mode = Mode.launch
    public private(set) var start: Date?
    public private(set) var readyAt: Double?
    public private(set) var skippedAt: Double?
    /// Where the creature lands, frozen at the first offer that comes in time.
    public private(set) var target: LaunchTarget?
    public private(set) var finished: Bool
    /// The moment it landed: the target creature's own clock starts here, so its first idle blink never doubles the landing's.
    public private(set) var landed: Date?
    public private(set) var reduceMotion = false
    /// The window's size, to tell whether the All set creature is in sight when the guide ends.
    @ObservationIgnored public var windowSize: CGSize = .zero
    @ObservationIgnored let slow: Double
    @ObservationIgnored let capture: Bool

    /// `finished` when the window opens with no splash (captures, demos, a window opened later).
    public init(finished: Bool = false, slow: Double = Theme.Motion.slow, capture: Bool = Theme.Motion.isCapture) {
        self.finished = finished || capture
        self.slow = max(1, slow)
        self.capture = capture
    }

    /// The splash's first frame. Once: a second appearance never restarts the scene.
    public func begin(at date: Date, reduceMotion: Bool) {
        guard start == nil else { return }
        start = date
        self.reduceMotion = reduceMotion
    }

    public func time(at date: Date) -> Double { start.map { date.timeIntervalSince($0) / slow } ?? 0 }

    /// The first load is done: the screens exist from now on, under the splash.
    public func ready(at date: Date) {
        guard readyAt == nil else { return }
        readyAt = max(0, time(at: date))
    }

    /// A click or a key on the splash: the hand-off starts as soon as the app is ready, even before 0.48 s.
    public func skip(at date: Date) {
        guard skippedAt == nil, mode == .launch, !finished else { return }
        skippedAt = time(at: date)
    }

    /// The earliest hand-off, on the scene's clock (the guide's exit starts at once).
    var handoffStart: Double? {
        switch mode {
        case .launch: LaunchDirector.handoffStart(readyAt: readyAt, skippedAt: skippedAt)
        case .exit: 0
        }
    }

    /// A creature to land on, measured on its first layout. Taken once, and only until the leap takes off: later, it would
    /// bend the arc mid-air (the creature then hops in place and fades, and the late one shows when the overlay goes).
    public func offer(_ candidate: LaunchTarget, at date: Date) {
        guard target == nil, !finished, candidate.unit > 0 else { return }
        if let hs = handoffStart, time(at: date) >= hs + Leap.anticipation { return }
        target = candidate
    }

    func input(size: CGSize) -> LaunchInput {
        LaunchInput(size: size, readyAt: readyAt, skippedAt: skippedAt, target: target, reduceMotion: reduceMotion)
    }

    /// The frame at a date.
    public func frame(at date: Date, size: CGSize) -> LaunchFrame {
        let t = time(at: date)
        switch mode {
        case .launch: return AssembleScene.frame(at: t, input(size: size))
        case .exit(let source): return GuideExit.frame(at: t, from: source, to: target, reduceMotion: reduceMotion)
        }
    }

    /// When the overlay goes, on the scene's clock; nil until the app is ready.
    public var finishTime: Double? {
        switch mode {
        case .launch: LaunchDirector.finishTime(input(size: windowSize))
        case .exit(let source): GuideExit.finishTime(from: source, to: target, reduceMotion: reduceMotion)
        }
    }

    /// The overlay drew its last frame: the target creature shows, its clock starting at the exact landing time.
    public func finish() {
        guard !finished else { return }
        finished = true
        if let start, let end = finishTime { landed = start.addingTimeInterval(end * slow) } else { landed = Date() }
    }

    /// "Open Brainmerge": the All set creature (its layout frame in the window) leaps into the sidebar while the guide fades
    /// out. Out of sight, or with Reduce Motion, the screens simply come in. Captures never play it.
    public func leave(from frame: CGRect?, reduceMotion: Bool, at date: Date) {
        let window = CGRect(origin: .zero, size: windowSize)
        let source = frame.flatMap { window.contains($0) && $0.width > 0 ? LaunchTarget(frame: $0, asleep: false) : nil }
        mode = .exit(source: source)
        start = date
        readyAt = nil
        skippedAt = nil
        target = nil
        landed = nil
        self.reduceMotion = reduceMotion
        finished = capture
    }

    // MARK: What the views read

    /// The splash's own backdrop, under everything while the launch runs.
    public var showsBackdrop: Bool { !finished && mode == .launch }
    /// The guide stays on screen, fading, while it leaps out of it.
    public var leavingGuide: Bool {
        guard !finished, case .exit = mode else { return false }
        return true
    }
    /// The creature being landed on is hidden until the overlay goes: never two creatures. Reduce Motion shows it at once.
    public var hidesTarget: Bool {
        guard !finished, !reduceMotion else { return false }
        switch mode {
        case .launch: return true
        case .exit(let source): return source != nil
        }
    }
    /// The All set creature, while its copy leaps out of the guide.
    public var hidesSource: Bool {
        guard !finished, !reduceMotion, case .exit(let source) = mode else { return false }
        return source != nil
    }
    /// The screens underneath need frames: after the load, until the overlay goes.
    public var revealRuns: Bool { !finished && (readyAt != nil || mode != .launch) }

    /// How the screens (or the guide) look at a date under the overlay.
    public func reveal(_ role: Role, at date: Date) -> (opacity: Double, scale: CGFloat, hittable: Bool) {
        guard !finished else { return (1, 1, true) }
        let f = frame(at: date, size: windowSize)
        if case .exit = mode, role == .guide { return (f.guideOpacity, 1, false) }
        return (f.screensOpacity, f.screensScale, true)
    }
}

/// The screens under a hand-off: their opacity and scale come from the launch clock, frame by frame. They fill the window,
/// so the window's space is named again on them, under the scale: a creature in them is measured where it will be once
/// they are whole (98.5% at first would land the leap a few points off).
struct LaunchReveal: ViewModifier {
    let clock: LaunchClock
    let role: LaunchClock.Role

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !clock.revealRuns)) { context in
            let look = clock.reveal(role, at: context.date)
            content
                .coordinateSpace(.named(LaunchClock.space))
                .opacity(look.opacity)
                .scaleEffect(look.scale)
                .allowsHitTesting(look.hittable)
                .accessibilityHidden(look.opacity == 0)
        }
    }
}

/// A creature a leap can land on: it tells the clock where it is on its first layout, and stays hidden until it lands.
struct LaunchTargetMark: ViewModifier {
    let clock: LaunchClock?
    let asleep: Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchClock.space)) } action: { frame in
                clock?.offer(LaunchTarget(frame: frame, asleep: asleep), at: Date())
            }
            .opacity(clock?.hidesTarget == true ? 0 : 1)
    }
}

extension View {
    /// Screens that fade in under the launch's leap (or the guide that fades out under the last one).
    func launchReveal(_ clock: LaunchClock, role: LaunchClock.Role) -> some View { modifier(LaunchReveal(clock: clock, role: role)) }
    /// A creature the launch can land on.
    func launchTarget(_ clock: LaunchClock?, asleep: Bool) -> some View { modifier(LaunchTargetMark(clock: clock, asleep: asleep)) }
}
