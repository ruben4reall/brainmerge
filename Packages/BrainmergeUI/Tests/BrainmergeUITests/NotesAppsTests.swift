import Foundation
import Testing
@testable import BrainmergeUI

@Suite struct NotesAppsTests {
    @Test func listsOnlyTheAppsPresentOnTheMac() {
        let present: Set<String> = ["md.obsidian", "dev.zed.Zed"]
        let found = NotesApps.installed { present.contains($0) ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        #expect(found.map(\.name) == ["Obsidian", "Zed"])
        #expect(NotesApps.installed { _ in nil }.isEmpty)
    }
    @Test func settingsResolveToATarget() {
        let obsidian = NotesApp(name: "Obsidian", bundleIdentifier: "md.obsidian", website: URL(string: "https://obsidian.md")!, location: URL(fileURLWithPath: "/Applications/Obsidian.app"))
        #expect(NotesApps.target(for: nil, installed: [obsidian]) == .folder)
        #expect(NotesApps.target(for: "md.obsidian", installed: [obsidian]) == .app(obsidian))
        #expect(NotesApps.target(for: "com.electron.logseq", installed: [obsidian]) == .folder)   // chosen app no longer installed
        #expect(NotesApps.target(for: "path:/Applications/Nova.app", installed: []) == .custom(URL(fileURLWithPath: "/Applications/Nova.app")))
        #expect(NotesApps.setting(for: .custom(URL(fileURLWithPath: "/Applications/Nova.app"))) == "path:/Applications/Nova.app")
    }

    @Test func knownAppsAreDistinctAndHaveWebsites() {
        #expect(Set(NotesApps.known.map(\.bundleIdentifier)).count == NotesApps.known.count)
        #expect(NotesApps.known.allSatisfy { $0.website.scheme == "https" })
    }
}
