import AppKit
import SwiftUI
import Testing
@testable import BrainmergeUI

@MainActor @Suite struct CreatureViewTests {
    /// The view takes exactly the grid's room in a layout (16 by 11 cells): its canvas overflows for hops and sparkles
    /// without growing the sidebar row or the onboarding step.
    @Test func theLayoutIsTheGridWhateverTheCanvas() {
        for (size, unit) in [(CGFloat(32), CGFloat(2)), (48, 3), (64, 4)] {
            for state in [CreatureState.awake, .asleep, .glowing] {
                let host = NSHostingView(rootView: CreatureView(state: state, size: size))
                #expect(host.fittingSize == CGSize(width: 16 * unit, height: 11 * unit), "\(size) \(state): \(host.fittingSize)")
            }
        }
    }

    /// The launch gives its landing creature the exact landing time. The view's clock reads it from the first frame after the
    /// hand-off, never its own appearance time (a frame could show mid-blink, or a pixel of breath, at the swap).
    @Test func aGivenClockStartWinsOverTheAppearance() {
        let appeared = Date(timeIntervalSinceReferenceDate: 800_000_000), landed = appeared.addingTimeInterval(1.2)
        let now = landed.addingTimeInterval(0.01)
        #expect(CreatureView.clockOrigin(clockStart: landed, appeared: appeared, now: now) == landed)
        #expect(CreatureView.clockOrigin(clockStart: nil, appeared: appeared, now: now) == appeared)
        #expect(CreatureView.clockOrigin(clockStart: nil, appeared: nil, now: now) == now)
    }

    /// The Canvas draws `drawnFrame`: the schedule's frame at the timeline's cadence. Held at a low frequency, a date that
    /// falls mid-hop draws the resting pose, never a hop frozen in the air.
    @Test func theCanvasDrawsTheScheduleAtTheTimelinesCadence() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let schedule = CreatureSchedule(start: now.addingTimeInterval(-0.2), mode: .live, state: .awake,
                                        events: [CreatureStamp(.memorySaved, at: 0)], profile: .companion, walking: nil, asleepSince: nil)
        let live = CreatureView.drawnFrame(schedule, at: now, cadence: .live)
        #expect(live == schedule.frame(at: now) && live.pose.offset.dy < -1)
        for cadence in [TimelineViewDefaultContext.Cadence.seconds, .minutes] {
            #expect(CreatureView.drawnFrame(schedule, at: now, cadence: cadence) == CreatureLife.restingFrame(.awake), "\(cadence)")
        }
    }

    /// The body goes through the tested helpers and nothing else: its Canvas draws `drawnFrame` with the timeline's cadence
    /// (without it, a timeline held at a low frequency froze a hop in the air), and its clock's origin is `clockOrigin`
    /// (reading the appearance first ignored the launch's landing time when it came after).
    @Test func theBodyDrawsThroughTheTestedHelpers() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Design/CreatureView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try #require(source.range(of: "    public var body: some View {"))
        let end = try #require(source.range(of: "    /// What the Canvas draws at a timeline date", range: start.upperBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])
        #expect(body.contains("Self.drawnFrame(schedule, at: context.date, cadence: context.cadence)"))
        #expect(!body.contains("frame(at:"), "the body draws only through drawnFrame")
        #expect(!body.contains("clockStart ??") && !body.contains("appeared ??"), "only clockOrigin picks the clock's start")
        #expect(source.contains("private var origin: Date { Self.clockOrigin(clockStart: clockStart, appeared: appeared, now: Date()) }"))
    }

    @Test func thePlacesUseTheirSizes() throws {
        // Sidebar 32 (2 pt cells, companion), welcome 64 (4 pt, stage), All set 48 (3 pt, stage).
        let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        let root = try String(contentsOf: screens.appending(path: "RootView.swift"), encoding: .utf8)
        let onboarding = try String(contentsOf: screens.appending(path: "OnboardingView.swift"), encoding: .utf8)
        #expect(root.contains("CreatureView(state: state, size: 32"))
        #expect(onboarding.contains("CreatureView(state: .awake, size: 64, profile: .stage"))
        #expect(onboarding.contains("CreatureView(state: .awake, size: 48, profile: .stage, events: [CreatureStamp(.memorySaved, at: AllSetBeat.hop)]"))
    }

    @Test func noAuraOrGlowAroundTheCreature() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Design/CreatureView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(!source.contains("AuraView") && !source.contains("glowOpacity") && !source.contains(".blur("))
        #expect(!source.contains(".animation("))
    }
}
