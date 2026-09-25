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

    /// With the icon, closing the window keeps Brainmerge in the menu bar; without it, closing the window quits.
    @Test func windowCloseKeepsRunningOnlyWithTheIcon() {
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: true) == false)
        #expect(AppLifecycle.quitsWhenLastWindowCloses(iconShown: false) == true)
    }

    /// A quit in the middle of a copy rebuild would leave a half-built app: it waits for the work to end.
    @Test func quitWaitsForWork() {
        #expect(AppLifecycle.terminateReply(workInProgress: true) == .terminateLater)
        #expect(AppLifecycle.terminateReply(workInProgress: false) == .terminateNow)
    }
}
