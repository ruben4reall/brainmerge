import AppKit
import Foundation
import Testing
@testable import BrainmergeUI

@Suite struct AppLifecycleTests {
    func shows(setting: Bool = true, phase: LaunchPhase = .ready, setupDone: Bool = true, _ environment: [String: String] = [:]) -> Bool {
        AppLifecycle.showsMenuBarIcon(setting: setting, phase: phase, setupDone: setupDone, environment: environment)
    }

    /// The icon waits for the splash and the guided setup, follows the setting, and never shows in a capture or a demo.
    @Test func iconWaitsForSetupAndDefaultsOn() {
        #expect(shows())
        #expect(!shows(phase: .loading))
        #expect(!shows(setupDone: false))
        #expect(!shows(setting: false))
        for key in ["BRAINMERGE_CAPTURE", "BRAINMERGE_SCREEN", "BRAINMERGE_ONBOARDING_STEP", "BRAINMERGE_HOME"] {
            #expect(!shows([key: "1"]), "\(key)")
            #expect(AppLifecycle.isCaptureOrDemo(environment: [key: "1"]), "\(key)")
        }
        // Only a demo home that is set counts; other variables change nothing.
        #expect(shows(["BRAINMERGE_HOME": ""]))
        #expect(shows(["BRAINMERGE_MEMORY_PRESSURE": "warning"]))
        #expect(!AppLifecycle.isCaptureOrDemo(environment: [:]))
    }

    /// With the icon, closing the window keeps Brainmerge in the menu bar; without it, closing the window quits,
    /// unless the quick opener's shortcut is registered: it works with the window closed.
    @Test func windowCloseKeepsRunningOnlyWithTheIconOrTheOpener() {
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: true, openerActive: false) == false)
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: false, openerActive: false) == true)
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: false, openerActive: true) == false)
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: true, openerActive: true) == false)
    }

    /// The icon dragged out of the menu bar with the window closed would leave Brainmerge with nothing to click but
    /// the Dock: the window opens again. With the window open, nothing more happens.
    @Test func removingTheIconWithNoWindowReopensIt() {
        #expect(AppLifecycle.reopensWindow(afterIconRemovedWith: false) == true)
        #expect(AppLifecycle.reopensWindow(afterIconRemovedWith: true) == false)
    }

    /// A window state AppKit saved for an older version (0.5 had a window group) would be restored to no window at all, and
    /// the one window would then never open: nothing is restored, and the old state is forgotten at launch, only it.
    @Test func noOldWindowStateKeepsTheWindowFromOpening() throws {
        #expect(!AppLifecycle.restoresWindows)
        let home = FileManager.default.temporaryDirectory.appending(path: "saved-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let saved = home.appending(path: "Library/Saved Application State", directoryHint: .isDirectory)
        let ours = saved.appending(path: "ch.rubencatalao.brainmerge.savedState", directoryHint: .isDirectory)
        let theirs = saved.appending(path: "com.anthropic.claudefordesktop.savedState", directoryHint: .isDirectory)
        for folder in [ours, theirs] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("window".utf8).write(to: folder.appending(path: "windows.plist"))
        }
        AppLifecycle.forgetSavedWindows(bundleID: "ch.rubencatalao.brainmerge", home: home)
        #expect(!FileManager.default.fileExists(atPath: ours.path))
        #expect(FileManager.default.fileExists(atPath: theirs.appending(path: "windows.plist").path))
        // Nothing to forget, or no bundle (tests, the command line): nothing happens.
        AppLifecycle.forgetSavedWindows(bundleID: "ch.rubencatalao.brainmerge", home: home)
        AppLifecycle.forgetSavedWindows(bundleID: nil, home: home)
        #expect(FileManager.default.fileExists(atPath: theirs.path))
    }

    /// A quit in the middle of a copy rebuild would leave a half-built app: it waits for the work to end.
    @Test func quitWaitsForWork() {
        #expect(AppLifecycle.terminateReply(workInProgress: true) == .terminateLater)
        #expect(AppLifecycle.terminateReply(workInProgress: false) == .terminateNow)
    }
}
