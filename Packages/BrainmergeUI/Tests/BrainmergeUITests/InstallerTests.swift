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
    /// Kept in memory: a test never writes a preferences file into the real ~/Library/Preferences.
    final class MemoryDefaults: DeclineStore {
        var values: [String: Any] = [:]
        func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    @Test func aDeclinedOfferIsRemembered() {
        let defaults = MemoryDefaults()
        #expect(!Installer.wasDeclined(bundlePath: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults))
        Installer.remember(declined: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults)
        #expect(Installer.wasDeclined(bundlePath: "/Volumes/Brainmerge/Brainmerge.app", defaults: defaults))
        #expect(defaults.values[Installer.declinedKey] as? [String] == ["/Volumes/Brainmerge/Brainmerge.app"])
    }

    /// No test of either package touches a real preferences domain: UserDefaults writes a plist into
    /// ~/Library/Preferences that outlives the run (110 of them had piled up).
    @Test func noTestWritesRealPreferences() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let core = ui.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "BrainmergeCore/Tests/BrainmergeCoreTests")
        let files = try [ui, core].flatMap { folder in
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        }
        #expect(files.count > 60)
        let banned = ["UserDefaults(", "UserDefaults.standard", "CFPreferencesSet", "defaults write"]
        for file in files {
            // This list itself names them.
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { !$0.contains("let banned = [") }
            for word in banned {
                #expect(!lines.contains { $0.contains(word) }, "\(file.lastPathComponent) uses \(word)")
            }
        }
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
