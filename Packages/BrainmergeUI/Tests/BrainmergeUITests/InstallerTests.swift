import Foundation
import Testing
@testable import BrainmergeUI

@Suite struct InstallerTests {
    @Test func offersToMoveOnlyWhenItHelps() {
        // From the disk image or Downloads: yes. Already in Applications, or a development build: no.
        #expect(Installer.shouldOfferMove(bundlePath: "/Volumes/Brainmerge/Brainmerge.app", home: "/Users/r", isReadOnly: true))
        // An external disk where the person keeps their apps: no prompt on every launch.
        #expect(!Installer.shouldOfferMove(bundlePath: "/Volumes/Externe/Apps/Brainmerge.app", home: "/Users/r", isReadOnly: false))
        #expect(Installer.shouldOfferMove(bundlePath: "/Users/r/Downloads/Brainmerge.app", home: "/Users/r", isReadOnly: false))
        #expect(!Installer.shouldOfferMove(bundlePath: "/Applications/Brainmerge.app", home: "/Users/r", isReadOnly: false))
        #expect(!Installer.shouldOfferMove(bundlePath: "/Users/r/Applications/Brainmerge.app", home: "/Users/r", isReadOnly: false))
        #expect(!Installer.shouldOfferMove(bundlePath: "/Users/r/brainmerge/.build/xcode/Build/Products/Debug/Brainmerge.app", home: "/Users/r", isReadOnly: false))
        #expect(!Installer.shouldOfferMove(bundlePath: "/Users/r/Library/Developer/Xcode/DerivedData/x/Brainmerge.app", home: "/Users/r", isReadOnly: false))
    }
    @Test func aDeclinedOfferIsRemembered() {
        let defaults = UserDefaults(suiteName: "brainmerge.tests.\(UUID().uuidString)")!
        #expect(!Installer.wasDeclined(bundlePath: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults))
        Installer.remember(declined: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults)
        #expect(Installer.wasDeclined(bundlePath: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults))
    }

    @Test func neverReplacesACopyThatIsRunning() {
        let target = URL(fileURLWithPath: "/Applications/Brainmerge.app")
        #expect(Installer.canReplace(target: target, running: [URL(fileURLWithPath: "/Volumes/Brainmerge/Brainmerge.app")]))
        #expect(!Installer.canReplace(target: target, running: [URL(fileURLWithPath: "/Volumes/Brainmerge/Brainmerge.app"), target]))
    }

    @Test func destinationIsTheApplicationsFolder() {
        #expect(Installer.destination(for: "/Volumes/Brainmerge/Brainmerge.app").path == "/Applications/Brainmerge.app")
    }
}
