import SwiftUI

/// The one clock of a hand-off: the splash overlay draws its frames, the screens underneath read their opacity from the
/// same frames, and the creature it lands on stays hidden until the overlay goes. One clock, never two animations.
///
/// Two scenes run on it: the launch (`AssembleScene`), then, on a first run, the end of the guided setup (`GuideExit`).
/// Times are seconds on the scene's clock since `start`, slowed by `BRAINMERGE_SLOW_MOTION` in debug builds.
///
/// The display drives it (`show(frameAt:)`, from `DisplayFrames`): each frame is worked out once, for the moment it reaches
/// the screen, and the scene's zero is its first frame shown. The creature, the guide and the screens under it read that
/// one frame, so a frame drawn late in its refresh is still drawn for its own moment: the steps stay even.
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
    /// How the screens (or the guide) look under the overlay: their opacity and scale, and whether they take clicks.
    public struct Look: Equatable, Sendable {
        public var opacity: Double
        public var scale: CGFloat
        public var hittable: Bool
        public static let whole = Look(opacity: 1, scale: 1, hittable: true)
    }

    public private(set) var mode = Mode.launch
    public private(set) var start: Date?
    public private(set) var readyAt: Double?
    public private(set) var skippedAt: Double?
    /// Where the creature lands, frozen at the first offer that comes in time.
    public private(set) var target: LaunchTarget?
    /// The last place a creature said it stands, even with no leap running: the sidebar, built under All set before
    /// "Open Brainmerge", says it there, and the guide's exit lands on it.
    @ObservationIgnored private var lastOffer: LaunchTarget?
    public private(set) var finished: Bool
    /// The moment it landed: the target creature's own clock starts here, so its first idle blink never doubles the landing's.
    public private(set) var landed: Date?
    public private(set) var reduceMotion = false
    /// The frame on screen now, worked out once for the moment the display shows it (nil before the scene's first one).
    public private(set) var current: LaunchFrame?
    /// How the screens and the guide look under it, set only when that changes: once a fade is over, the frames still
    /// coming for the creature redraw neither.
    private var mainLook = Look.whole
    private var guideLook = Look.whole
    /// The scene waits for its first frame shown to set its zero there.
    @ObservationIgnored private var anchoring = false
    /// The window's size, to tell whether the All set creature is in sight when the guide ends.
    @ObservationIgnored public var windowSize: CGSize = .zero
    /// Where the All set creature stands, kept for "Open Brainmerge": it moves on every scroll step, and outside
    /// observation it never redraws the guide.
    @ObservationIgnored public var allSetFrame: CGRect?
    /// The words and rows on screen, by id: the leap flies around them. They follow the layout, except while a creature
    /// is in the air (they would bend its arc).
    @ObservationIgnored private var obstacleFrames: [String: CGRect] = [:]
    /// The hand-off worked out for the last inputs: finding a clear way is too much work for every frame.
    /// Two entries: the splash and the screens under it may ask with sizes that differ by a fraction of a point.
    @ObservationIgnored private var launchPlans: [(input: LaunchInput, plan: LaunchDirector.Handoff?)] = []
    @ObservationIgnored private var exitPlan: (key: [CGRect], source: LaunchTarget?, target: LaunchTarget?, reduce: Bool, plan: GuideExit.Plan?)?
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
        anchoring = true
        self.reduceMotion = reduceMotion
        updateLooks(frame(at: date, size: windowSize))
    }

    /// The display shows a frame at `date`: the first one of a scene becomes its zero, and the frame is worked out once for
    /// everyone who draws from it. The frame that reaches the end lands the scene.
    public func show(frameAt date: Date) {
        guard !finished, let start else { return }
        if anchoring {
            anchoring = false
            let shift = date.timeIntervalSince(start) / slow
            self.start = date
            readyAt = readyAt.map { max(0, $0 - shift) }
            skippedAt = skippedAt.map { max(0, $0 - shift) }
        }
        let frame = frame(at: date, size: windowSize)
        current = frame
        updateLooks(frame)
        if frame.finished { finish() }
    }

    /// What the overlay draws: the frame shown now, or, before the display's first frame of a scene, its very first one
    /// (never a frame a few milliseconds in that the first one shown would then take back).
    public func drawnFrame(size: CGSize) -> LaunchFrame {
        current ?? frame(at: anchoring ? (start ?? Date()) : Date(), size: size)
    }

    /// How `role` looks now: whole once the scene is over.
    public func look(_ role: Role) -> Look {
        guard !finished else { return .whole }
        return role == .main ? mainLook : guideLook
    }

    private func updateLooks(_ frame: LaunchFrame) {
        let main = look(.main, in: frame), guide = look(.guide, in: frame)
        if main != mainLook { mainLook = main }
        if guide != guideLook { guideLook = guide }
    }

    private func look(_ role: Role, in f: LaunchFrame) -> Look {
        if case .exit = mode, role == .guide { return Look(opacity: f.guideOpacity, scale: 1, hittable: false) }
        return Look(opacity: f.screensOpacity, scale: f.screensScale, hittable: !f.screensHeld)
    }

    public func time(at date: Date) -> Double { start.map { date.timeIntervalSince($0) / slow } ?? 0 }

    /// The first load is done: the screens exist from now on, under the splash.
    public func ready(at date: Date) {
        guard readyAt == nil else { return }
        readyAt = max(0, time(at: date))
        if !finished { updateLooks(frame(at: date, size: windowSize)) }
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
        guard candidate.unit > 0 else { return }
        lastOffer = candidate
        guard target == nil, !finished else { return }
        if let hs = handoffStart, time(at: date) >= hs + Leap.anticipation { return }
        target = candidate
    }

    /// Words or rows on screen at `frame` (nil: gone). Held while a leap is in the air.
    public func offer(obstacle id: String, frame: CGRect?, at date: Date) {
        if !finished, let hs = handoffStart, time(at: date) >= hs + Leap.anticipation { return }
        obstacleFrames[id] = frame
    }

    /// What the leap flies around: the obstacles in the window, never an empty one.
    var obstacles: [CGRect] {
        let window = CGRect(origin: .zero, size: windowSize)
        return obstacleFrames.keys.sorted().compactMap { id in
            guard let frame = obstacleFrames[id], frame.width > 0, frame.height > 0 else { return nil }
            let inside = windowSize == .zero ? frame : frame.intersection(window)
            return inside.isNull || inside.isEmpty ? nil : inside
        }
    }

    func input(size: CGSize) -> LaunchInput {
        LaunchInput(size: size, readyAt: readyAt, skippedAt: skippedAt, target: target, reduceMotion: reduceMotion, obstacles: obstacles)
    }

    /// The frame at a date.
    public func frame(at date: Date, size: CGSize) -> LaunchFrame {
        let t = time(at: date)
        switch mode {
        case .launch:
            let input = input(size: size)
            return LaunchDirector.frame(at: t, input, plan: plan(for: input))
        case .exit(let source):
            return GuideExit.frame(at: t, from: source, to: target, plan: exit(from: source), reduceMotion: reduceMotion)
        }
    }

    /// The launch's hand-off for these inputs, worked out once.
    func plan(for input: LaunchInput) -> LaunchDirector.Handoff? {
        if let cached = launchPlans.first(where: { $0.input == input }) { return cached.plan }
        let plan = input.reduceMotion ? nil : LaunchDirector.handoff(input)
        launchPlans = Array(([(input, plan)] + launchPlans).prefix(2))
        return plan
    }

    /// The guide's last leap for the current source, target and obstacles, worked out once.
    func exit(from source: LaunchTarget?) -> GuideExit.Plan? {
        let obstacles = obstacles
        if let c = exitPlan, c.key == obstacles, c.source == source, c.target == target, c.reduce == reduceMotion { return c.plan }
        let plan = GuideExit.plan(from: source, to: target, obstacles: obstacles, reduceMotion: reduceMotion)
        exitPlan = (obstacles, source, target, reduceMotion, plan)
        return plan
    }

    /// The guide's first words on a first run (title, text, button, note: `index` 0 to 3): they wait for the welcome
    /// creature to land, then come in one after the other (0.05 s apart, 0.30 s each, rising 6 pt), so its leap never
    /// crosses them. At once with Reduce Motion, with nowhere to land, and in every later window.
    public func words(_ index: Int, at date: Date) -> (opacity: Double, rise: CGFloat) {
        let input = input(size: windowSize)
        guard wordsRun, let touchdown = LaunchDirector.touchdown(input, plan: plan(for: input)) else { return (1, 0) }
        let k = Ease.out(Ease.progress(time(at: date), from: touchdown + 0.05 * Double(index), over: Self.wordsFade))
        return (k, CGFloat(6 * (1 - k)))
    }
    static let wordsFade = 0.30
    /// The words still wait or come in: the launch is running.
    public var wordsRun: Bool { !finished && mode == .launch && !reduceMotion }

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
        current = nil
        anchoring = false
        if let start, let end = finishTime { landed = start.addingTimeInterval(end * slow) } else { landed = Date() }
    }

    /// "Open Brainmerge": the All set creature (its layout frame in the window) leaps into the sidebar while the guide fades
    /// out. Out of sight, or with Reduce Motion, the screens simply come in. Captures never play it.
    public func leave(from frame: CGRect?, reduceMotion: Bool, at date: Date) {
        let window = CGRect(origin: .zero, size: windowSize)
        let source = frame.flatMap { window.contains($0) && $0.width > 0 ? LaunchTarget(frame: $0, asleep: false) : nil }
        mode = .exit(source: source)
        start = date
        anchoring = true
        readyAt = nil
        skippedAt = nil
        target = lastOffer
        landed = nil
        current = nil
        self.reduceMotion = reduceMotion
        finished = capture
        if !finished { updateLooks(self.frame(at: date, size: windowSize)) }
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
    /// How the screens (or the guide) look at a date under the overlay.
    public func reveal(_ role: Role, at date: Date) -> Look {
        guard !finished else { return .whole }
        return look(role, in: frame(at: date, size: windowSize))
    }
}

/// The screens under a hand-off, or the guide over the last one: their opacity comes from the launch clock's frame on
/// screen, and they are drawn again only when it changes. They fill the window, so the window's space is named again on
/// them.
///
/// The main window is never faded itself: a group opacity over its glass re-renders every backdrop on every frame of the
/// leap. A cover of the window's own background fades off it instead, which looks the same (the window is opaque over
/// that background) and leaves the screens untouched: only the cover is drawn again. While the screens are held back,
/// the cover takes the clicks. The guide, over the main window, fades itself. `held`: the main window built under All
/// set, not revealed yet (see `HeldUnderGuide`), which VoiceOver never reaches either.
struct LaunchReveal: ViewModifier {
    let clock: LaunchClock
    let role: LaunchClock.Role
    var held = false

    func body(content: Content) -> some View {
        switch role {
        case .main:
            let look = clock.look(.main)
            content
                .coordinateSpace(.named(LaunchClock.space))
                .overlay { WarmBackground().opacity(1 - look.opacity).allowsHitTesting(!look.hittable) }
                // One say for VoiceOver on this window, never two that could undo each other.
                .accessibilityHidden(!HeldUnderGuide.Look(held: held).accessible
                                     || (!clock.finished && clock.mode == .launch && clock.readyAt == nil))
        case .guide:
            let look = clock.look(.guide)
            content
                .coordinateSpace(.named(LaunchClock.space))
                .opacity(look.opacity)
                .allowsHitTesting(look.hittable)
                .accessibilityHidden(look.opacity == 0)
        }
    }
}

/// The main window built under All set before "Open Brainmerge": laid out already, so nothing is laid out for the first
/// time while the creature is in the air, and out of reach until then: unseen, no clicks, its controls off (no Return,
/// Space, Tab or shortcut reaches them), and nothing for VoiceOver (`LaunchReveal` says it, with `held`).
struct HeldUnderGuide: ViewModifier {
    let held: Bool

    struct Look: Equatable {
        var opacity: Double
        var hittable: Bool
        var enabled: Bool
        var accessible: Bool
        init(opacity: Double, hittable: Bool, enabled: Bool, accessible: Bool) {
            self.opacity = opacity; self.hittable = hittable; self.enabled = enabled; self.accessible = accessible
        }
        init(held: Bool) { self.init(opacity: held ? 0 : 1, hittable: !held, enabled: !held, accessible: !held) }
    }

    func body(content: Content) -> some View {
        let look = Look(held: held)
        content.opacity(look.opacity).allowsHitTesting(look.hittable).disabled(!look.enabled)
    }
}

/// A creature a leap can land on: it tells the clock where it is, and whether it sleeps, as they change, and stays hidden
/// until it lands.
struct LaunchTargetMark: ViewModifier {
    let clock: LaunchClock?
    let asleep: Bool
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchClock.space)) } action: { frame in
                self.frame = frame
                clock?.offer(LaunchTarget(frame: frame, asleep: asleep), at: Date())
            }
            .onChange(of: asleep) { _, asleep in
                if let frame { clock?.offer(LaunchTarget(frame: frame, asleep: asleep), at: Date()) }
            }
            .opacity(clock?.hidesTarget == true ? 0 : 1)
    }
}

/// Words or rows a leap must not fly over: they tell the clock where they are, and that they are gone.
struct LaunchObstacleMark: ViewModifier {
    @Environment(LaunchClock.self) private var clock: LaunchClock?
    let id: String

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchClock.space)) } action: { frame in
                clock?.offer(obstacle: id, frame: frame, at: Date())
            }
            .onDisappear { clock?.offer(obstacle: id, frame: nil, at: Date()) }
    }
}

/// One of the guide's first words on a first run: it waits for the welcome creature to land (see `LaunchClock.words`).
struct LaunchWords: ViewModifier {
    @Environment(LaunchClock.self) private var clock: LaunchClock?
    let index: Int

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: clock?.wordsRun != true)) { context in
            let look: (opacity: Double, rise: CGFloat) = clock?.words(index, at: context.date) ?? (1, 0)
            content.opacity(look.opacity).offset(y: look.rise)
        }
    }
}

extension View {
    /// Words or rows on screen: the launch's leaps fly around them.
    func launchObstacle(_ id: String) -> some View { modifier(LaunchObstacleMark(id: id)) }
    /// One of the welcome's words, which come in once the launch's creature has landed above them.
    func launchWords(_ index: Int) -> some View { modifier(LaunchWords(index: index)) }
    /// Screens that fade in under the launch's leap (or the guide that fades out under the last one). `held`: the main
    /// window built under All set, not revealed yet.
    func launchReveal(_ clock: LaunchClock, role: LaunchClock.Role, held: Bool = false) -> some View {
        modifier(LaunchReveal(clock: clock, role: role, held: held))
    }
    /// A creature the launch can land on.
    func launchTarget(_ clock: LaunchClock?, asleep: Bool) -> some View { modifier(LaunchTargetMark(clock: clock, asleep: asleep)) }
}
