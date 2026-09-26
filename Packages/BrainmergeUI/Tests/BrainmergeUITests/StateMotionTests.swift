import Foundation
import SwiftUI
import Testing
@testable import BrainmergeUI

/// The state changes that used to pop: every beat is a pure function of the time since it started, so a screen seen
/// later draws it over, and a capture draws its end.
@Suite struct StateMotionTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Beats and their frames

    @Test func aBeatCountsFromItsStartAndNothingWithout() {
        #expect(Beat.elapsed(since: nil, at: start) == nil)
        #expect(Beat.elapsed(since: start, at: start.addingTimeInterval(0.25)) == 0.25)
        // A beat seen before it starts has not begun.
        #expect(Beat.elapsed(since: start, at: start.addingTimeInterval(-1)) == 0)
    }

    /// Sixty frames a second while the beat plays, then none: the last frame holds and nothing redraws for it.
    @Test func aBeatAsksForFramesOnlyWhileItPlays() {
        let schedule = BeatSchedule(start: start, duration: 0.5)
        let dates = schedule.entries(from: start, mode: .normal)
        #expect(dates.first == start)
        #expect(dates.last == .distantFuture)
        let frames = dates.dropLast()
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $1.timeIntervalSince($0) > 0 && $1.timeIntervalSince($0) <= 1.0 / 60 + 1e-9 })
        #expect((frames.last?.timeIntervalSince(start) ?? 0) >= 0.5)
        #expect(frames.count <= 33)
        // Over, or never started: no frame beyond the one drawn now.
        #expect(schedule.entries(from: start.addingTimeInterval(2), mode: .normal) == [start.addingTimeInterval(2), .distantFuture])
        #expect(BeatSchedule(start: nil, duration: 0.5).entries(from: start, mode: .normal) == [start, .distantFuture])
        // Low frequency: the start and the end only.
        let low = schedule.entries(from: start, mode: .lowFrequency)
        #expect(low.count == 3 && low[1] >= start.addingTimeInterval(0.5) && low[2] == .distantFuture)
    }

    /// A screen whose first frame comes late (a hitch as it is built) still plays its beat whole: the beat counts from that
    /// frame. A screen seen long after (a later visit) finds it over.
    @Test func aLateFirstFrameStillPlaysTheWholeBeat() {
        #expect(Beat.origin(start: start, firstFrame: start.addingTimeInterval(0.11)) == start.addingTimeInterval(0.11))
        #expect(Beat.origin(start: start, firstFrame: start.addingTimeInterval(5)) == start)
        #expect(Beat.origin(start: start, firstFrame: nil) == start)
        #expect(Beat.origin(start: nil, firstFrame: start) == nil)
    }

    /// A chart that arrives below the fold grows when it is first seen, not offscreen; built on a later visit, it is in place.
    @Test func aChartGrowsWhenItIsFirstSeen() {
        let arrived = start
        // Built with the arrival, not seen yet: waiting at its baseline.
        #expect(Beat.visibleOrigin(arrived: arrived, built: arrived.addingTimeInterval(0.05), seen: nil) == .waiting)
        #expect(Beat.visibleOrigin(arrived: arrived, built: arrived.addingTimeInterval(0.05), seen: arrived.addingTimeInterval(4)) == .from(arrived.addingTimeInterval(4)))
        #expect(Beat.visibleOrigin(arrived: arrived, built: arrived.addingTimeInterval(0.05), seen: arrived.addingTimeInterval(0.05)) == .from(arrived.addingTimeInterval(0.05)))
        // A later visit, or nothing arrived: in place.
        #expect(Beat.visibleOrigin(arrived: arrived, built: arrived.addingTimeInterval(30), seen: arrived.addingTimeInterval(31)) == .from(arrived))
        #expect(Beat.visibleOrigin(arrived: nil, built: arrived, seen: nil) == .inPlace)
    }

    // MARK: M1, an account opening

    /// The stroke turns once every 1.6 s from its own start; captures and Reduce Motion hold it at 35 degrees.
    @Test func theOpeningStrokeTurnsOncePerPeriod() {
        #expect(OpeningStroke.angle(elapsed: 0, still: false) == 0)
        #expect(abs(OpeningStroke.angle(elapsed: 0.4, still: false) - 90) < 1e-9)
        #expect(abs(OpeningStroke.angle(elapsed: 1.6, still: false)) < 1e-9)
        #expect(OpeningStroke.angle(elapsed: 12.3, still: true) == 35)
        #expect(OpeningStroke.opacity(reduceMotion: false) == 1 && OpeningStroke.opacity(reduceMotion: true) == 0.6)
        #expect(OpeningStroke.fadeIn == 0.18 && OpeningStroke.fadeOut == 0.25)
    }

    /// The stroke reads on a dark glass card: 2.5 points, a third of the way round at full tint (not a sliver), and a
    /// tighter, brighter glow.
    @Test func theOpeningStrokeIsReadable() {
        #expect(OpeningStroke.lineWidth == 2.5 && OpeningStroke.glowBlur == 4 && OpeningStroke.glowOpacity == 0.6)
        let stops = OpeningStroke.stops
        #expect(stops.first?.location == 0 && stops.last?.location == 1)
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location })
        // How much of the way round is at full tint: the full stops' spans at each end.
        let full = stops.filter { $0.opacity == 1 }.map(\.location)
        let head = full.filter { $0 < 0.5 }.max() ?? 0, tail = 1 - (full.filter { $0 > 0.5 }.min() ?? 1)
        #expect(head + tail >= 0.15, "\(stops)")
        // At least 30% of the way round is lit above half.
        let lit = (0..<1000).filter { OpeningStroke.opacity(at: Double($0) / 1000) > 0.5 }.count
        #expect(lit >= 300, "\(lit)")
    }

    // MARK: Text that changes

    /// A line that changes (a status, a subtitle, the creature's line, a button's word): the old words leave before the
    /// new ones settle, so no frame shows both above 25%.
    @Test func aSwappedLineNeverShowsTwoStringsAtOnce() {
        for i in 0...96 {
            let t = Double(i) / 240, o = SwapText.opacities(at: t)
            #expect(min(o.old, o.new) <= 0.25, "t \(t): \(o)")
        }
        #expect(SwapText.opacities(at: 0).old == 1 && SwapText.opacities(at: 0).new == 0)
        #expect(SwapText.opacities(at: 0.4) == (old: 0, new: 1))
        #expect(SwapText.removal + SwapText.delay <= 0.2 && SwapText.delay + SwapText.insertion <= 0.25)
    }

    /// Opened: one sage ring from the 6 point dot to 18 points, fading from 0.8, in 0.5 s on the ease-out.
    @Test func theOpenedRingSpreadsOnceAndIsGone() {
        let ring = RingPulse.opened
        #expect(ring.look(elapsed: nil) == nil)
        #expect(ring.look(elapsed: 0) == RingPulse.Look(diameter: 6, opacity: 0.8))
        let mid = ring.look(elapsed: 0.25)
        #expect((mid?.diameter ?? 0) > 12 && (mid?.diameter ?? 99) < 18)
        #expect((mid?.opacity ?? 1) < 0.4)
        #expect(ring.look(elapsed: 0.5) == nil)
        #expect(ring.lineWidth == 1.5)
        // The card's orb, a new account: the same spread around a 40 point orb; the graph's status dot, 6 to 16 in 0.6 s.
        #expect(RingPulse.added.from == 40 && RingPulse.added.to == 52 && RingPulse.added.duration == 0.5)
        #expect(RingPulse.changed.from == 6 && RingPulse.changed.to == 16 && RingPulse.changed.duration == 0.6)
    }

    /// The dot pops from 0.4 on the pop spring and rests at exactly 1; with Reduce Motion it only fades.
    @Test func theOpenedDotPopsToRest() {
        #expect(PopIn.scale(elapsed: nil, reduceMotion: false) == 1)
        #expect(PopIn.scale(elapsed: 0, reduceMotion: false) == 0.4)
        #expect(abs(PopIn.scale(elapsed: PopIn.duration - 0.001, reduceMotion: false) - 1) < 0.01)
        #expect(PopIn.scale(elapsed: PopIn.duration, reduceMotion: false) == 1)
        let peak = stride(from: 0.0, to: PopIn.duration, by: 1.0 / 120).map { PopIn.scale(elapsed: $0, reduceMotion: false) }.max() ?? 0
        #expect(peak > 1.02)   // a spring, not a fade
        #expect(PopIn.scale(elapsed: 0, reduceMotion: true) == 1)
        #expect(PopIn.opacity(elapsed: 0, reduceMotion: true) == 0 && PopIn.opacity(elapsed: 0.15, reduceMotion: true) == 1)
        #expect(PopIn.opacity(elapsed: 0, reduceMotion: false) == 1)
    }

    // MARK: Arrivals

    /// Data arriving rises 8 points and fades in over 0.24 s; lines drop 4 points in 0.18 s; timeline rows drop 6.
    @Test func anArrivalRisesIntoPlaceOnce() {
        let data = Arrival.data
        #expect(data.duration == 0.24 && data.offset == 8)
        #expect(Arrival.line.duration == 0.18 && Arrival.line.offset == -4)
        #expect(Arrival.row.duration == 0.24 && Arrival.row.offset == -6)
        // Nothing seen arriving (a later visit, a capture): in place.
        #expect(data.look(elapsed: nil, reduceMotion: false) == Arrival.Look(opacity: 1, offset: 0))
        #expect(data.look(elapsed: 0, reduceMotion: false) == Arrival.Look(opacity: 0, offset: 8))
        let mid = data.look(elapsed: 0.12, reduceMotion: false)
        #expect(mid.opacity > 0.5 && mid.opacity < 1 && mid.offset > 0 && mid.offset < 4)
        #expect(data.look(elapsed: 0.24, reduceMotion: false) == Arrival.Look(opacity: 1, offset: 0))
        // A delay holds it back; the delayed one ends later.
        let late = data.delayed(0.1)
        #expect(late.look(elapsed: 0.09, reduceMotion: false) == Arrival.Look(opacity: 0, offset: 8))
        #expect(abs(late.end - 0.34) < 1e-9)
        // Reduce Motion: a 0.15 s fade in place.
        #expect(data.look(elapsed: 0, reduceMotion: true) == Arrival.Look(opacity: 0, offset: 0))
        #expect(data.look(elapsed: 0.075, reduceMotion: true).offset == 0)
        #expect(data.look(elapsed: 0.15, reduceMotion: true) == Arrival.Look(opacity: 1, offset: 0))
    }

    /// A new save in the timeline: the selection color from full to nothing over 1.6 s, so it can be found.
    @Test func aNewRowsHighlightFadesOverOnePointSixSeconds() {
        #expect(Highlight.opacity(elapsed: nil) == 0)
        #expect(Highlight.opacity(elapsed: 0) == 1)
        #expect(Highlight.opacity(elapsed: 0.8) > 0.1 && Highlight.opacity(elapsed: 0.8) < 0.5)
        #expect(Highlight.opacity(elapsed: 1.6) == 0)
        #expect(Highlight.duration == 1.6)
    }

    // MARK: M4, Usage

    @Test func usageCardsAndBarsArriveInOrder() {
        #expect(zip((0..<6).map(UsageMotion.cardDelay), [0, 0.05, 0.1, 0.15, 0.2, 0.2]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(UsageMotion.barDelay(0) == 0 && abs(UsageMotion.barDelay(13) - 0.195) < 1e-9)
        // From the 2 point baseline to full height, the first bar before the last (today's).
        let first = { (e: Double) in UsageMotion.barHeight(fraction: 1, height: 40, index: 0, elapsed: e, reduceMotion: false) }
        let today = { (e: Double) in UsageMotion.barHeight(fraction: 1, height: 40, index: 13, elapsed: e, reduceMotion: false) }
        #expect(first(0) == 2 && today(0) == 2)
        #expect(first(0.1) > today(0.1))
        #expect(first(0.35) == 40 && today(0.195 + 0.35) == 40)
        #expect(UsageMotion.barHeight(fraction: 0.5, height: 40, index: 3, elapsed: nil, reduceMotion: false) == 20)
        // An empty day keeps its 2 point stub; Reduce Motion draws the bars at their height.
        #expect(UsageMotion.barHeight(fraction: 0, height: 40, index: 3, elapsed: nil, reduceMotion: false) == 2)
        #expect(UsageMotion.barHeight(fraction: 1, height: 40, index: 3, elapsed: 0, reduceMotion: true) == 40)
        #expect(UsageMotion.duration == 0.2 + 0.24 && UsageMotion.barsDuration == 0.195 + 0.35)
    }

    // MARK: M6, a sheet's inline problem

    /// The same sentence set again is a second failure: it shakes. Another sentence crossfades; a cleared one enters again.
    @Test func theSameProblemAgainShakes() {
        var problem = InlineProblem()
        problem.show("Give this memory a name.")
        #expect(problem.text == "Give this memory a name." && problem.repeats == 0)
        problem.show("Give this memory a name.")
        #expect(problem.repeats == 1)
        problem.show("Quit Work first, then try again.")
        #expect(problem.repeats == 1 && problem.text == "Quit Work first, then try again.")
        problem.show(nil)
        #expect(problem.text == nil)
        problem.show("Quit Work first, then try again.")
        #expect(problem.repeats == 1)
    }

    /// A sentence that is not a refusal (a choice that worked) drops in like a problem but never shakes, even said twice;
    /// a refusal after it enters again instead of shaking.
    @Test func aGoodNewsLineNeverShakes() {
        var line = InlineProblem()
        line.note("Brainmerge uses this Claude from its next launch.")
        line.note("Brainmerge uses this Claude from its next launch.")
        #expect(line.text == "Brainmerge uses this Claude from its next launch." && line.repeats == 0)
        line.show("Not signed by Anthropic.")
        line.note("Brainmerge uses this Claude from its next launch.")
        line.show("Not signed by Anthropic.")
        #expect(line.repeats == 0)
        line.show("Not signed by Anthropic.")
        #expect(line.repeats == 1)
    }

    /// x 0, -4, 4, -3, 0 over 0.3 s; with Reduce Motion an opacity blink 1, 0.4, 1 instead.
    @Test func theShakeIsShortAndEndsInPlace() {
        #expect(Shake.offsets.map(\.value) == [-4, 4, -3, 0])
        #expect(abs(Shake.offsets.map(\.duration).reduce(0, +) - 0.3) < 1e-9)
        #expect(Shake.blink.map(\.value) == [0.4, 1])
        #expect(abs(Shake.blink.map(\.duration).reduce(0, +) - 0.3) < 1e-9)
    }

    /// No problem and no work: nothing at all, so a sheet keeps its spacing (an empty view would still take a stack's gap).
    @MainActor @Test func anAbsentLineTakesNoRoom() {
        func height(_ view: some View) -> CGFloat { NSHostingView(rootView: view).fittingSize.height }
        let bare = height(VStack(spacing: 14) { Text("a"); Text("b") })
        #expect(height(VStack(spacing: 14) { Text("a"); ProblemLine(problem: InlineProblem()); WorkingLine(text: nil); Text("b") }) == bare)
        var shown = InlineProblem()
        shown.show("Give this memory a name.")
        #expect(height(VStack(spacing: 14) { Text("a"); ProblemLine(problem: shown); Text("b") }) > bare)
        #expect(height(VStack(spacing: 14) { Text("a"); WorkingLine(text: "Creating the memory…"); Text("b") }) > bare)
    }

    /// A long working sentence wraps next to a sheet's buttons instead of losing its end ("…and Stu…").
    @MainActor @Test func aLongWorkingSentenceWraps() {
        func height(_ text: String) -> CGFloat { NSHostingView(rootView: WorkingLine(text: text).frame(width: 200)).fittingSize.height }
        #expect(height("Swapping the names of Personal and Studio in every app and folder…") > height("Saving…") * 1.5)
    }

    // MARK: E4 to E6, the sidebar

    /// Press in at once; release and hover in 0.12 s; nothing with Reduce Motion. The selection moves with the screen, at
    /// once: the pill never lags behind the screen it names.
    @Test func aPressIsInstantAndTheRestTakesTwelveHundredths() {
        #expect(SidebarRowStyle.fillAnimation(pressed: true, reduceMotion: false) == nil)
        #expect(SidebarRowStyle.fillAnimation(pressed: false, reduceMotion: false) == Theme.Motion.out(Theme.Motion.hover))
        #expect(SidebarRowStyle.fillAnimation(pressed: false, reduceMotion: true) == nil)
        #expect(SidebarRowStyle.selectionAnimation == nil)
        #expect(SidebarRowStyle.pointerFill(pressed: false, hovering: true) == Theme.Colors.rowHover)
        #expect(SidebarRowStyle.pointerFill(pressed: true, hovering: true) == Theme.Colors.rowPressed)
        #expect(SidebarRowStyle.pointerFill(pressed: false, hovering: false) == .clear)
    }
}
