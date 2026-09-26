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

    @Test func theMainWindowReportsItsWordsAndRows() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.offersMove = { false }
        await model.launch(minimum: .zero)
        let size = CGSize(width: 960, height: 640)
        let clock = LaunchClock(finished: true, slow: 1, capture: false)
        clock.windowSize = size
        let window = TimelineDrawingTests.window(for: RootView(model: model, launch: clock).frame(width: size.width, height: size.height))
        window.setContentSize(size)
        Self.spin(0.6)
        let obstacles = clock.input(size: size).obstacles
        window.orderOut(nil)
        model.windowDisappeared(); model.stopWatching()
        // The sidebar's title and screens, its two rows, the creature's line, the Accounts header and cards.
        let sidebar = obstacles.filter { $0.maxX < 232 }
        #expect(sidebar.contains { $0.minY < 80 }, "the title: \(obstacles)")
        #expect(sidebar.filter { $0.minY > 240 && $0.maxY < 400 }.count == 2, "two rows: \(obstacles)")
        #expect(sidebar.contains { $0.minY > 580 && $0.minX > 60 }, "the creature's line: \(obstacles)")
        #expect(obstacles.contains { $0.minX > 240 && $0.minY < 60 && $0.maxY > 150 }, "the header and cards: \(obstacles)")
        // Never where the creature lands, nor in the empty lower window.
        let footer = CGRect(x: 26, y: size.height - 44, width: 32, height: 22)
        #expect(!obstacles.contains { $0.intersects(footer) })
        #expect(!obstacles.contains { $0.intersects(CGRect(x: 300, y: 400, width: 600, height: 150)) })
    }
}
