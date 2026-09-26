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
    /// Each tile's icon is looked up once with the apps (a tile never asks macOS for its icon as it draws).
    @Test func findGivesEveryTileItsIcon() throws {
        let found = NotesApps.find { $0 == "md.obsidian" ? URL(fileURLWithPath: "/Applications/Obsidian.app") : nil }
        #expect(found.apps.map(\.name) == ["Obsidian"])
        let obsidian = try #require(found.apps.first)
        #expect(found.icon(for: .folder) != nil && found.icon(for: .app(obsidian)) != nil)
        #expect(found.icon(for: .custom(URL(fileURLWithPath: "/Applications/Nova.app"))) == nil)
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

    @Test func obsidianReceivesTheWholePathWhateverItsCharacters() throws {
        let url = try #require(NotesApps.obsidianURL(for: URL(fileURLWithPath: "/Brain/memory/web/Q&A + notes=1#2?.md")))
        #expect(url.absoluteString == "obsidian://open?path=/Brain/memory/web/Q%26A%20%2B%20notes%3D1%232%3F.md")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "path" }?.value == "/Brain/memory/web/Q&A + notes=1#2?.md")
    }
}
