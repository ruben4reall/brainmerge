import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// The graph's source menu: every Brainmerge memory, then every Obsidian vault.
@Suite struct GraphSourcesTests {
    let shared = MemoryFolder(id: "shared", name: "Shared", path: "/Users/x/Brain")
    let work = MemoryFolder(id: "work", name: "Work", path: "/Users/x/Brain-work")
    let notes = URL(fileURLWithPath: "/Users/x/Documents/Notes Vault", isDirectory: true)
    let studio = URL(fileURLWithPath: "/Users/x/Studio", isDirectory: true)

    @Test func oneMemoryIsTheBrainmergeMemory() {
        let menu = GraphSources.menu(brains: [shared], vaults: [notes, studio], chosen: nil)
        #expect(menu.memories.map(\.name) == ["Brainmerge memory"])
        #expect(menu.memories.map(\.source) == [.memory("shared")])
        #expect(menu.vaults.map(\.name) == ["Notes Vault", "Studio"])
        #expect(menu.vaults.map(\.source) == [.vault(notes.path), .vault(studio.path)])
        #expect(GraphSources.title(of: .memory("shared"), brains: [shared]) == "Brainmerge memory")
        #expect(GraphSources.title(of: .vault(notes.path), brains: [shared]) == "Notes Vault")
    }

    @Test func severalMemoriesAreNamed() {
        let menu = GraphSources.menu(brains: [shared, work], vaults: [], chosen: nil)
        #expect(menu.memories.map(\.name) == ["Shared", "Work"])
        #expect(GraphSources.title(of: .memory("work"), brains: [shared, work]) == "Brainmerge memory · Work")
    }

    /// A vault picked by hand that Obsidian does not list shows while it is the one shown, once.
    @Test func aChosenVaultIsListedOnce() {
        let picked = "/Users/x/Elsewhere/Archive"
        #expect(GraphSources.menu(brains: [shared], vaults: [notes], chosen: picked).vaults.map(\.name) == ["Archive", "Notes Vault"])
        #expect(GraphSources.menu(brains: [shared], vaults: [notes], chosen: notes.path + "/").vaults.count == 1)
    }

    /// Two vaults with one name are told apart by the folder they sit in.
    @Test func vaultsWithOneNameAreToldApart() {
        let other = URL(fileURLWithPath: "/Users/x/Work/Notes Vault", isDirectory: true)
        #expect(GraphSources.menu(brains: [shared], vaults: [notes, other], chosen: nil).vaults.map(\.name)
                == ["Notes Vault · Documents", "Notes Vault · Work"])
    }
}
