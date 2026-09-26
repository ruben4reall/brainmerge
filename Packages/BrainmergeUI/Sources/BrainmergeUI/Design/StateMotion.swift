import SwiftUI

// State changes that used to pop: an account that opens, data that arrives, a result, an error, a row. Each beat is a pure
// function of the time since the moment it answers (a date the model or the screen keeps), so a screen seen later finds
// it over and draws its end, and a capture always draws the end. Values: MOTION.md, section 5.1.

/// The time since a beat started, on the app's slow-motion clock.
enum Beat {
    /// Seconds since `start` at `date` (0 before it), divided by BRAINMERGE_SLOW_MOTION; nil without a start.
    static func elapsed(since start: Date?, at date: Date) -> Double? {
        start.map { max(0, date.timeIntervalSince($0)) / Theme.Motion.slow }
    }

    /// Where a beat counts from in a view whose first frame came at `firstFrame`: that frame, when it came late for a beat
    /// that had just started (a hitch as the screen was built would otherwise eat its entrance); the beat's own start when
    /// the view came long after (a later visit finds it over).
    static let lateFrameGrace = 0.5
    static func origin(start: Date?, firstFrame: Date?) -> Date? {
        guard let start else { return nil }
        guard let firstFrame, firstFrame > start, firstFrame.timeIntervalSince(start) < lateFrameGrace * Theme.Motion.slow else { return start }
        return firstFrame
    }

    /// Where the beat of something built with an arrival but maybe out of sight (a chart below the fold) counts from.
    enum Visible: Equatable { case inPlace, waiting, from(Date) }
    static func visibleOrigin(arrived: Date?, built: Date, seen: Date?) -> Visible {
        guard let arrived else { return .inPlace }
        // Built on a later visit: the beat is long over.
        guard built.timeIntervalSince(arrived) < 1 else { return .from(arrived) }
        guard let seen else { return .waiting }
        return .from(max(arrived, seen))
    }
}

/// The frames a beat asks for: sixty a second from its start until it ends, then none, so its last frame holds and a
/// screen at rest costs nothing. SwiftUI draws the first entry at once and never the last one (a far-future wait).
struct BeatSchedule: TimelineSchedule {
    var start: Date?
    /// In seconds of the beat's own clock (BRAINMERGE_SLOW_MOTION stretches it).
    var duration: Double

    func entries(from date: Date, mode: TimelineScheduleMode) -> [Date] {
        guard let start else { return [date, .distantFuture] }
        let end = start.addingTimeInterval(duration * Theme.Motion.slow)
        guard end > date else { return [date, .distantFuture] }
        if mode == .lowFrequency { return [date, end.addingTimeInterval(0.001), .distantFuture] }
        var dates = [date]
        var next = date.addingTimeInterval(1.0 / 60)
        while next < end { dates.append(next); next = next.addingTimeInterval(1.0 / 60) }
        return dates + [end.addingTimeInterval(0.001), .distantFuture]
    }
}

/// Draws a beat from its elapsed time (nil: none seen, or a capture): the view only draws frames. A first frame that came
/// late counts as the beat's start (`Beat.origin`): the whole beat still plays.
struct BeatView<Content: View>: View {
    let start: Date?
    let duration: Double
    @ViewBuilder let content: (Double?) -> Content
    /// When this view was first drawn: kept outside observation, set once.
    @State private var drawn = FirstDraw()

    final class FirstDraw { var date: Date? }

    var body: some View {
        let first = drawn.date ?? { let now = Date(); drawn.date = now; return now }()
        let start = Theme.Motion.isCapture ? nil : Beat.origin(start: self.start, firstFrame: first)
        TimelineView(BeatSchedule(start: start, duration: duration)) { context in
            content(Beat.elapsed(since: start, at: context.date))
        }
    }
}

// MARK: M1, an account opening

/// The stroke around an opening account's card, in its own color: a bright arc that turns once every 1.6 s, and the
/// same stroke blurred under it. It fades in over 0.18 s and out over 0.25 s. Captures and Reduce Motion hold it still
/// at 35 degrees, and Reduce Motion draws it at 60%. Drawn inside the card's glass, 2.5 points wide with a third of the
/// way round lit: at the spec's 1.5 points and a sliver of tint, the glass washed it out.
enum OpeningStroke {
    static let period = 1.6
    static let lineWidth: CGFloat = 2.5
    static let glowBlur: CGFloat = 4
    static let glowOpacity = 0.6
    static let stillAngle = 35.0
    static let fadeIn = 0.18, fadeOut = 0.25

    /// Along the way round from the arc's head: full tint for 15%, fading out to 45%, dark, back in from 85%.
    struct Stop: Equatable { var location: Double; var opacity: Double }
    static let stops = [Stop(location: 0, opacity: 1), Stop(location: 0.15, opacity: 1), Stop(location: 0.45, opacity: 0),
                        Stop(location: 0.85, opacity: 0), Stop(location: 1, opacity: 1)]
    /// The tint's opacity at a place along the way round (0 to 1).
    static func opacity(at x: Double) -> Double {
        guard let next = stops.firstIndex(where: { $0.location >= x }) else { return stops.last?.opacity ?? 0 }
        guard next > 0 else { return stops[0].opacity }
        let a = stops[next - 1], b = stops[next]
        return Ease.lerp(a.opacity, b.opacity, (x - a.location) / max(1e-9, b.location - a.location))
    }

    /// Degrees, from the stroke's own start.
    static func angle(elapsed: Double, still: Bool) -> Double {
        still ? stillAngle : (elapsed / period).truncatingRemainder(dividingBy: 1) * 360
    }
    static func opacity(reduceMotion: Bool) -> Double { reduceMotion ? 0.6 : 1 }
}

/// The opening stroke, drawn on a card's rounded rectangle.
struct OpeningStrokeView: View {
    let tint: Color
    var cornerRadius: CGFloat = Theme.Layout.cardRadius
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Its own start, taken when it appears: the arc always begins its turn at the top.
    @State private var start = Date()

    var body: some View {
        let still = reduceMotion || Theme.Motion.isCapture
        TimelineView(.animation(paused: still)) { context in
            let elapsed = Beat.elapsed(since: start, at: context.date) ?? 0
            Frame(tint: tint, angle: OpeningStroke.angle(elapsed: elapsed, still: still),
                  opacity: OpeningStroke.opacity(reduceMotion: reduceMotion), cornerRadius: cornerRadius)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One frame of it: the arc at `angle` degrees, and its glow.
    struct Frame: View {
        let tint: Color
        let angle: Double
        var opacity = 1.0
        var cornerRadius: CGFloat = Theme.Layout.cardRadius

        var body: some View {
            let gradient = AngularGradient(stops: OpeningStroke.stops.map { Gradient.Stop(color: tint.opacity($0.opacity), location: $0.location) },
                                           center: .center, angle: .degrees(angle))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: OpeningStroke.lineWidth)
                    .blur(radius: OpeningStroke.glowBlur).opacity(OpeningStroke.glowOpacity)
                shape.strokeBorder(gradient, lineWidth: OpeningStroke.lineWidth)
            }
            .opacity(opacity)
        }
    }
}

/// One ring that spreads from a dot or an orb and fades: an account opened, a card added, the graph changed.
struct RingPulse: Equatable {
    var from: CGFloat
    var to: CGFloat
    var duration: Double
    var peak = 0.8
    var lineWidth: CGFloat = 1.5

    /// The card's status dot when its account opens (sage).
    static let opened = RingPulse(from: 6, to: 18, duration: 0.5)
    /// A new card's orb (in the account's tint): the same spread around 40 points.
    static let added = RingPulse(from: 40, to: 52, duration: 0.5)
    /// The graph's status dot when the memory changes (accentLight).
    static let changed = RingPulse(from: 6, to: 16, duration: 0.6)

    struct Look: Equatable { var diameter: CGFloat; var opacity: Double }

    /// Nil when there is nothing to draw: no beat, or over.
    func look(elapsed: Double?) -> Look? {
        guard let elapsed, elapsed < duration else { return nil }
        let e = Ease.out(elapsed / duration)
        return Look(diameter: from + (to - from) * e, opacity: peak * (1 - e))
    }
}

struct RingPulseView: View {
    let ring: RingPulse
    let start: Date?
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BeatView(start: reduceMotion ? nil : start, duration: ring.duration) { elapsed in
            if let look = ring.look(elapsed: elapsed) {
                Circle().stroke(color, lineWidth: ring.lineWidth)
                    .frame(width: look.diameter, height: look.diameter)
                    .opacity(look.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A dot that turns on with a pop: from 0.4 of its size on the pop spring (0.35, 0.6) to exactly its size. With Reduce
/// Motion it keeps its size and fades in over 0.15 s.
enum PopIn {
    static let from = 0.4
    static let spring = Ease.Spring(response: 0.35, damping: 0.6)
    static let duration = 0.9

    static func scale(elapsed: Double?, reduceMotion: Bool) -> CGFloat {
        guard let elapsed, !reduceMotion, elapsed < duration else { return 1 }
        return CGFloat(from + (1 - from) * spring.value(elapsed))
    }
    static func opacity(elapsed: Double?, reduceMotion: Bool) -> Double {
        guard let elapsed, reduceMotion else { return 1 }
        return Ease.progress(elapsed, from: 0, over: Theme.Motion.reducedDuration)
    }
}

// MARK: M4, M6, M10: things that arrive

/// Something that arrives after a wait (data, a result, a new row): it moves `offset` points into place and fades in on
/// the ease-out, after `delay`. Nothing seen arriving (a later visit, a capture): in place. Reduce Motion: a 0.15 s fade.
struct Arrival: Equatable {
    var delay = 0.0
    var duration: Double
    /// Where it starts, in points below (positive) or above (negative) its place.
    var offset: CGFloat

    /// Data and results: 8 points up into place in 0.24 s (M4).
    static let data = Arrival(duration: 0.24, offset: 8)
    /// A line, a problem, a small result: 4 points down into place in 0.18 s (M6).
    static let line = Arrival(duration: 0.18, offset: -4)
    /// A new row at the top of the timeline: 6 points down into place in 0.24 s (M10).
    static let row = Arrival(duration: 0.24, offset: -6)

    func delayed(_ seconds: Double) -> Arrival { var copy = self; copy.delay = seconds; return copy }
    /// When it is in place, from its start.
    var end: Double { delay + duration }

    struct Look: Equatable { var opacity: Double; var offset: CGFloat }

    func look(elapsed: Double?, reduceMotion: Bool) -> Look {
        guard let elapsed else { return Look(opacity: 1, offset: 0) }
        if reduceMotion { return Look(opacity: Ease.progress(elapsed, from: delay, over: Theme.Motion.reducedDuration), offset: 0) }
        let e = Ease.out(Ease.progress(elapsed, from: delay, over: duration))
        return Look(opacity: e, offset: offset * CGFloat(1 - e))
    }
}

/// Plays an arrival from `start` (nil: in place).
struct ArrivalModifier: ViewModifier {
    let arrival: Arrival
    let start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        BeatView(start: start, duration: max(arrival.end, arrival.delay + Theme.Motion.reducedDuration)) { elapsed in
            let look = arrival.look(elapsed: elapsed, reduceMotion: reduceMotion)
            content.opacity(look.opacity).offset(y: look.offset)
        }
    }
}

extension View {
    /// Moves into place and fades in from `start` (see `Arrival`); in place without one.
    func arrives(_ arrival: Arrival, from start: Date?) -> some View { modifier(ArrivalModifier(arrival: arrival, start: start)) }
}

/// A new save in the timeline: its row wears the selection color, fading from full to nothing over 1.6 s, so it can
/// be found. A plain ease, the curve for color changes: it stays readable for most of its time.
enum Highlight {
    static let duration = 1.6
    static func opacity(elapsed: Double?) -> Double {
        guard let elapsed, elapsed < duration else { return 0 }
        return 1 - Ease.ease(elapsed / duration)
    }
}

/// The Usage screen's cards and bars when the first read replaces the placeholder: cards 50 ms apart (the fifth and
/// later ones together), each chart's bars growing from a 2 point baseline, 15 ms apart from left to right, so today's
/// bar comes last. Later reads update in place.
enum UsageMotion {
    static let cardStagger = 0.05
    static let barStagger = 0.015
    static let barGrowth = 0.35
    static let baseline: CGFloat = 2
    /// An update: the bars move to their new height, the figures roll to their new value.
    static let update = 0.3

    static func cardDelay(_ index: Int) -> Double { Double(min(index, 4)) * cardStagger }
    static func barDelay(_ index: Int) -> Double { Double(index) * barStagger }
    /// Every card in place.
    static var duration: Double { cardDelay(4) + Arrival.data.duration }
    /// Every bar of a chart grown, from its card's start (14 bars).
    static var barsDuration: Double { barDelay(13) + barGrowth }

    /// A bar's height: its share of the tallest day, never under the baseline; growing from the baseline while the
    /// chart arrives (`elapsed` since its card's start; nil: in place). Reduce Motion: at its height.
    static func barHeight(fraction: Double, height: CGFloat, index: Int, elapsed: Double?, reduceMotion: Bool) -> CGFloat {
        let full = max(baseline, height * CGFloat(fraction))
        guard let elapsed, !reduceMotion else { return full }
        let e = Ease.out(Ease.progress(elapsed, from: barDelay(index), over: barGrowth))
        return baseline + (full - baseline) * CGFloat(e)
    }
}

// MARK: M6, a sheet's inline problem

/// A sheet's inline problem: the sentence shown, and how many times the same one came back (each shakes the line: a second
/// failed click would otherwise change nothing on screen).
struct InlineProblem: Equatable {
    private(set) var text: String?
    private(set) var repeats = 0

    mutating func show(_ new: String?) {
        if let new, new == text, !isNote { repeats += 1 }
        text = new
        isNote = false
    }

    /// A sentence that is not a refusal (a choice that worked): it drops in the same way and never shakes.
    mutating func note(_ new: String) {
        text = new
        isNote = true
    }

    private var isNote = false
}

/// The shake of a problem said again: x 0, -4, 4, -3, 0 over 0.3 s, each step on the ease-out. With Reduce Motion, an
/// opacity blink 1, 0.4, 1 instead.
enum Shake {
    struct Key { let value: Double; let duration: Double }
    static let offsets = [Key(value: -4, duration: 0.075), Key(value: 4, duration: 0.075), Key(value: -3, duration: 0.075), Key(value: 0, duration: 0.075)]
    static let blink = [Key(value: 0.4, duration: 0.15), Key(value: 1, duration: 0.15)]
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1), endControlPoint: UnitPoint(x: 0.32, y: 1))
}

/// A problem under a form: it drops in (4 points, 0.18 s), crossfades to another sentence, shakes when said again.
/// Without a problem it is nothing at all: its stack keeps its spacing as before.
struct ProblemLine: View {
    let problem: InlineProblem
    var color: Color = Theme.Colors.accentLight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animation = Theme.Motion.unlessReduced(Theme.Motion.out(Arrival.line.duration), reduceMotion)
        if let text = problem.text {
            Text(text).foregroundStyle(color).font(Theme.Fonts.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(animation, value: text)
                .shakes(problem.repeats)
                .transition(AnyTransition.line(reduceMotion).animation(animation))
        }
    }
}

struct ShakeModifier: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: ShakeFrame(), trigger: trigger) { view, frame in
            view.offset(x: frame.x).opacity(frame.opacity)
        } keyframes: { _ in
            // Reduce Motion: the line stays in place and blinks instead.
            let x = reduceMotion ? Shake.offsets.map { Shake.Key(value: 0, duration: $0.duration) } : Shake.offsets
            let o = reduceMotion ? Shake.blink : Shake.blink.map { Shake.Key(value: 1, duration: $0.duration) }
            let slow = Theme.Motion.slow, curve = Shake.curve
            KeyframeTrack(\ShakeFrame.x) {
                LinearKeyframe(CGFloat(x[0].value), duration: x[0].duration * slow, timingCurve: curve)
                LinearKeyframe(CGFloat(x[1].value), duration: x[1].duration * slow, timingCurve: curve)
                LinearKeyframe(CGFloat(x[2].value), duration: x[2].duration * slow, timingCurve: curve)
                LinearKeyframe(CGFloat(x[3].value), duration: x[3].duration * slow, timingCurve: curve)
            }
            KeyframeTrack(\ShakeFrame.opacity) {
                LinearKeyframe(o[0].value, duration: o[0].duration * slow, timingCurve: curve)
                LinearKeyframe(o[1].value, duration: o[1].duration * slow, timingCurve: curve)
            }
        }
    }
}

struct ShakeFrame { var x: CGFloat = 0; var opacity = 1.0 }

extension View {
    /// Shakes each time `trigger` changes (see `Shake`).
    func shakes(_ trigger: Int) -> some View { modifier(ShakeModifier(trigger: trigger)) }
}

// MARK: Text that changes

/// Words that change in place (a status, a subtitle, the creature's line, a button's word): the old words lift away in
/// 0.10 s, the new ones settle in over 0.16 s from 0.06 s, so no frame shows the two above a quarter. A crossfade in place
/// printed two strings of different lengths over each other for a few frames. Reduce Motion: the same order, no lift.
enum SwapText {
    static let removal = 0.10, delay = 0.06, insertion = 0.16
    static let lift: CGFloat = 3

    static func opacities(at t: Double) -> (old: Double, new: Double) {
        (1 - Ease.out(Ease.progress(t, from: 0, over: removal)), Ease.out(Ease.progress(t, from: delay, over: insertion)))
    }

    static func transition(_ reduceMotion: Bool) -> AnyTransition {
        let leave = Theme.Motion.out(removal), come = Theme.Motion.out(insertion).delay(delay * Theme.Motion.slow)
        if reduceMotion { return .asymmetric(insertion: AnyTransition.opacity.animation(come), removal: AnyTransition.opacity.animation(leave)) }
        return .asymmetric(insertion: AnyTransition.opacity.combined(with: .offset(y: lift)).animation(come),
                           removal: AnyTransition.opacity.combined(with: .offset(y: -lift)).animation(leave))
    }
}

/// A line of text whose words swap in order (see `SwapText`). `key` says what counts as new words: a figure inside them
/// that moves every few seconds (a RAM size) changes in place, never swaps.
struct SwappingText: View {
    let text: String
    var key: String?
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: alignment) {
            Text(text).id(key ?? text).transition(SwapText.transition(reduceMotion))
        }
        .animation(Theme.Motion.out(SwapText.insertion), value: key ?? text)
    }
}

// MARK: M2, busy

/// A waiting sentence while work runs: a small spinner before its first line, the pair fading in and out in 0.15 s, a new
/// sentence swapping in after the old one. A long sentence wraps, never loses its end. Never a spinner inside a disabled
/// button. `holdsPlace`: one line's room stays when there is no work, so what is under it never jumps as it comes and goes.
struct WorkingLine: View {
    let text: String?
    var size: ControlSize = .small
    var holdsPlace = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animation = Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion)
        if holdsPlace {
            ZStack {
                line("Working…").hidden()
                if let text { line(text).transition(AnyTransition.opacity.animation(animation)) }
            }
        } else if let text {
            line(text).transition(AnyTransition.opacity.animation(animation))
        }
    }

    func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ProgressView().controlSize(size)
                // Centered on the first line's x-height, not sitting on its baseline.
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            SwappingText(text: text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// With Reduce Motion, a view that appears fades in over 0.15 s in place while the layout around it moves at once (a
/// banner, a block): no slide. Without it, the transition the screen gives it plays instead.
struct ReducedFadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!reduceMotion || shown || Theme.Motion.isCapture ? 1 : 0)
            .onAppear { if reduceMotion { withAnimation(Theme.Motion.reduced) { shown = true } } }
    }
}

// MARK: Transitions

extension AnyTransition {
    /// A fade. With Reduce Motion it carries its own 0.15 s, so it plays in place while the layout around it, which gets
    /// no animation then (`Theme.Motion.layout`), changes at once.
    static func fade(_ reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity.animation(Theme.Motion.reduced) : .opacity }
    /// A line coming in: 4 points down into place and a fade (M6). A fade in place with Reduce Motion.
    static func line(_ reduceMotion: Bool) -> AnyTransition { reduceMotion ? .fade(true) : .opacity.combined(with: .offset(y: Arrival.line.offset)) }
    /// A banner: 6 points down into place and a fade (M5).
    static func banner(_ reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)) }
    /// A block of data or of results: 8 points up into place and a fade (M4).
    static func arrival(_ reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Arrival.data.offset)) }
}
