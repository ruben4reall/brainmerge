import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Names end up in file names, plists, git authors and Claude's instructions: one line, no control characters, bounded.
@Suite struct NameRulesTests {
    @Test func namesAreOneCleanLine() {
        #expect(NameRules.clean("  Work\nAccount  ") == "Work Account")
        #expect(NameRules.clean("Tab\there\u{0}") == "Tab here")
        #expect(NameRules.clean("...Hidden") == "Hidden")
        #expect(NameRules.clean(String(repeating: "a", count: 100)).count == NameRules.maxLength)
        #expect(NameRules.clean("Élodie et Cie") == "Élodie et Cie")
        #expect(NameRules.clean(" \n ").isEmpty)
    }

    @Test func theManagerCleansAndRefusesEmptyNames() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(throws: BrainmergeError.nameInvalid) { try e.manager.add(IdentityManager.AddRequest(name: " \n ")) }
        let identity = try e.manager.add(IdentityManager.AddRequest(name: "Work\nStudio"))
        #expect(identity.name == "Work Studio" && identity.slug == "work-studio")
        #expect(FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Work Studio").path))
        #expect(throws: BrainmergeError.nameInvalid) { try e.manager.update(slug: identity.slug, name: "  ", tint: nil, logo: nil) }
        let folder = try e.manager.addBrain(name: " Client\r\nNotes ", path: nil, language: .en)
        #expect(folder.name == "Client Notes" && folder.id == "client-notes")
    }
}
