import AppKit
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The main window, hosted off every screen, tells the launch clock where its words and rows are: the leaps fly around them.
@MainActor @Suite(.serialized) struct LaunchObstacleTests {
    /// Runs the main run loop for a while: the hosted view lays out and reports.
    static func spin(_ seconds: Double) {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// The main window at `size` with these accounts, hosted off every screen: its words and rows (as a finished clock
    /// hears them) and where its footer creature stands (offered to a live clock, as at launch).
    static func mainWindow(_ names: [String], size: CGSize) async throws -> (obstacles: [CGRect], footer: LaunchTarget?) {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        if let first = names.first {
            _ = try e.manager.adoptPrimary(name: first)
            for name in names.dropFirst() { _ = try e.manager.add(IdentityManager.AddRequest(name: name)) }
        }
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.offersMove = { false }
        await model.launch(minimum: .zero)
        defer { model.windowDisappeared(); model.stopWatching() }
        func host(_ clock: LaunchClock) {
            clock.windowSize = size
            let window = TimelineDrawingTests.window(for: RootView(model: model, launch: clock).frame(width: size.width, height: size.height))
            window.setContentSize(size)
            Self.spin(0.6)
            window.orderOut(nil)
        }
        let shown = LaunchClock(finished: true, slow: 1, capture: false)
        host(shown)
        let live = LaunchClock(slow: 1, capture: false)
        host(live)
        return (shown.input(size: size).obstacles, live.target)
    }

    @Test func theMainWindowReportsItsWordsAndRows() async throws {
        let size = CGSize(width: 960, height: 640)
        let obstacles = try await Self.mainWindow(["Personal", "Work"], size: size).obstacles
        // The sidebar's title and screens, its two rows, the creature's line.
        let sidebar = obstacles.filter { $0.maxX < 232 }
        #expect(sidebar.contains { $0.minY < 80 }, "the title: \(obstacles)")
        #expect(sidebar.filter { $0.minY > 240 && $0.maxY < 400 }.count == 2, "two rows: \(obstacles)")
        #expect(sidebar.contains { $0.minY > 580 && $0.minX > 60 }, "the creature's line: \(obstacles)")
        // The Accounts header, then each card's words, orb and buttons, side by side in one row: never the cards' empty
        // edges, which the leap may pass in front of.
        let main = obstacles.filter { $0.minX > 240 }
        #expect(main.count == 3, "the header and two cards: \(main)")
        let header = try #require(main.min { $0.minY < $1.minY })
        #expect(header.minY < 60 && header.width > 600, "the header: \(header)")
        let cards = main.filter { $0 != header }
        #expect(cards.count == 2 && cards.allSatisfy { $0.minY > header.maxY && $0.width < 330 && $0.height < 60 }, "the cards: \(cards)")
        #expect(Set(cards.map(\.minY)).count == 1, "one row: \(cards)")
        // Never where the creature lands, nor in the empty lower window.
        let footer = CGRect(x: 26, y: size.height - 44, width: 32, height: 22)
        #expect(!obstacles.contains { $0.intersects(footer) })
        #expect(!obstacles.contains { $0.intersects(CGRect(x: 300, y: 400, width: 600, height: 150)) })
    }

    /// The default window (960 by 640) with four accounts: the splash's creature stands just under the second row of cards.
    /// Only their words, orbs and buttons are in the way, never their empty edges: the launch leaps up from the splash with
    /// its push and its stretch (the spec's leap, not a dive off a ledge), and a hand-off in the middle of the splash's hop
    /// never keeps the screens waiting. While the screens show, the creature is never over a word or a row.
    @Test func theDefaultWindowLeapsUpAndNeverHoldsTheScreens() async throws {
        let size = CGSize(width: 960, height: 640)
        let (obstacles, target) = try await Self.mainWindow(["Personal", "Work", "Studio", "Client"], size: size)
        let footer = try #require(target)
        let fast = try #require(LaunchDirector.handoff(LaunchInput(size: size, readyAt: 0.2, target: footer, obstacles: obstacles)))
        let route = try #require(fast.leap).route, held = fast.held
        #expect(route.apex > 0 && route.stretch > 0 && !held, "route \(route), held \(held)")
        // The frames are pure: worked out off the main actor, which the other suites' models need meanwhile.
        let problems = await Task.detached {
            var problems: [String] = []
            for i in 0...25 {
                let ready = 0.60 + Double(i) * 0.02
                let inp = LaunchInput(size: size, readyAt: ready, target: footer, obstacles: obstacles)
                guard let plan = LaunchDirector.handoff(inp) else { problems.append("ready \(ready): no hand-off"); continue }
                if plan.held { problems.append(String(format: "ready %.2f: the screens wait until %.2f", ready, plan.screensStart)) }
                var t = plan.start
                while t < plan.finish {
                    let f = LaunchDirector.frame(at: t, inp, plan: plan)
                    if f.screensOpacity > 0, let o = obstacles.first(where: { LaunchSceneTests.covers(f, $0) }) {
                        problems.append(String(format: "ready %.2f t %.3f over %@", ready, t, "\(o)"))
                    }
                    t += 1.0 / 120
                }
            }
            return problems
        }.value
        #expect(problems.isEmpty, "\(problems.prefix(8))")
    }
}
