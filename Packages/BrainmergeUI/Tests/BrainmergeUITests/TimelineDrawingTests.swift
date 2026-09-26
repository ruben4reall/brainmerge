import AppKit
import SwiftUI
import Testing
@testable import BrainmergeUI

/// What SwiftUI really draws from the sidebar's timelines, in a window. It draws a schedule's first entry at once, even one
/// in the future, and never its last one: the schedules are built around that, and these tests pin it.
@MainActor @Suite(.serialized) struct TimelineDrawingTests {
    @MainActor final class Log { var dates: [Date] = [] }
    @MainActor @Observable final class Glow { var ends: Date? }

    /// The sidebar footer's timeline, as RootView builds it: its body reads the glow's end, so a save restarts it.
    struct Footer: View {
        let glow: Glow
        let log: Log
        var body: some View {
            TimelineView(GlowSchedule(ends: glow.ends)) { context in
                let _ = log.dates.append(context.date)
                Color.clear.frame(width: 10, height: 10)
            }
        }
    }

    /// A borderless window holding `view`, ordered in but placed beyond every screen: SwiftUI draws it on the real run
    /// loop, and nothing ever shows on the display.
    static func window<V: View>(for view: V) -> NSWindow {
        let screens = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let away = screens.isNull ? CGPoint(x: -20_000, y: -20_000) : CGPoint(x: screens.minX - 20_000, y: screens.minY - 20_000)
        let window = NSWindow(contentRect: NSRect(origin: away, size: CGSize(width: 120, height: 90)), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.setFrameOrigin(away)   // borderless: never constrained back onto a screen
        window.orderFrontRegardless()
        return window
    }

    /// Shows `view` in a window off the screens and runs the main run loop for `seconds`, calling each action at its time.
    static func host<V: View>(_ view: V, for seconds: Double, actions: [(at: Double, run: () -> Void)] = []) {
        let window = Self.window(for: view)
        let start = Date()
        var pending = actions
        while Date().timeIntervalSince(start) < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            while let next = pending.first, Date().timeIntervalSince(start) >= next.at { next.run(); pending.removeFirst() }
        }
        window.orderOut(nil)
    }

    /// The hosting window runs the real run loop but is never seen: it stands outside every screen.
    @Test func theHostWindowIsOffEveryScreen() {
        let window = Self.window(for: Color.clear)
        defer { window.orderOut(nil) }
        #expect(!NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "\(window.frame)")
    }

    @Test func aReactionEndsOnItsSettledFrame() throws {
        // Asleep for more than a minute (its timeline was still), then a save: the hop plays and the creature lands asleep,
        // eyes closed, no sparkle left in the air.
        let now = Date()
        let schedule = CreatureSchedule(start: now.addingTimeInterval(-70), mode: .live, state: .asleep,
                                        events: [CreatureStamp(.memorySaved, at: 70.15)], profile: .companion, walking: nil, asleepSince: 0)
        let log = Log()
        Self.host(TimelineView(schedule) { context in
            let _ = log.dates.append(context.date)
            Color.clear.frame(width: 10, height: 10)
        }, for: 1.6)
        #expect(log.dates.count > 10, "the hop was not drawn: \(log.dates.count) frames")
        let last = try #require(log.dates.last)
        #expect(schedule.frame(at: last) == LifeFrame(pose: .asleep), "stuck on \(schedule.frame(at: last))")
    }

    @Test func theGlowScheduleDrawsNowTheEndThenWaits() {
        let now = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let ends = now.addingTimeInterval(4)
        #expect(Array(GlowSchedule(ends: ends).entries(from: now, mode: .normal)) == [now, ends.addingTimeInterval(0.001), .distantFuture])
        // Over, or no save yet: only now. Never a date inside a glow that is over (a window reopened later, a restart).
        #expect(Array(GlowSchedule(ends: now.addingTimeInterval(-1)).entries(from: now, mode: .normal)) == [now, .distantFuture])
        #expect(Array(GlowSchedule(ends: nil).entries(from: now, mode: .normal)) == [now, .distantFuture])
    }

    @Test func aSaveIsDrawnGlowingThenClearedWhenTheGlowEnds() throws {
        // A save at 0.3 s whose glow lasts 1 s (4 s in the app): the footer is drawn inside the glow right away, then again
        // once it is over. (`.explicit([ends])` drew only the end, at once: the glow and its line never showed.)
        let glow = Glow(), log = Log()
        var saved: Date?
        Self.host(Footer(glow: glow, log: log), for: 1.9, actions: [(0.3, { saved = Date(); glow.ends = saved?.addingTimeInterval(1) })])
        let s = try #require(saved), ends = s.addingTimeInterval(1)
        #expect(log.dates.contains { $0 >= s && $0 < ends }, "never drawn glowing: \(log.dates.map { $0.timeIntervalSince(s) })")
        let last = try #require(log.dates.last)
        #expect(last >= ends, "the end of the glow was never drawn: \(log.dates.map { $0.timeIntervalSince(s) })")
    }

    @Test func aFooterBuiltAfterTheGlowNeverShowsIt() {
        // The window reopened 2 s after a save whose glow lasted 1 s: nothing is drawn at a date inside that glow.
        let glow = Glow(), log = Log()
        let built = Date()
        glow.ends = built.addingTimeInterval(-1)
        Self.host(Footer(glow: glow, log: log), for: 0.3)
        #expect(!log.dates.isEmpty && log.dates.allSatisfy { $0 >= built.addingTimeInterval(-0.001) }, "\(log.dates.map { $0.timeIntervalSince(built) })")
    }
}
