import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct AppStateTests {
    @Test func identitiesResolveTheirMemory() {
        var state = AppState(machineID: "m")
        state.brains = [MemoryFolder(id: "shared", name: "Shared", path: "/x/Brain"), MemoryFolder(id: "work", name: "Work", path: "/x/Brain-work")]
        let perso = Identity(slug: "perso", name: "Perso", isPrimary: true)
        var work = Identity(slug: "work", name: "Work")
        work.brain = "work"
        var stale = Identity(slug: "stale", name: "Stale")
        stale.brain = "gone"
        // No memory named: the default one. A named one: that one. A memory that no longer exists: the default one.
        #expect(state.brain(for: perso)?.id == "shared")
        #expect(state.brain(for: work)?.id == "work")
        #expect(state.brain(for: stale)?.id == "shared")
        #expect(state.defaultBrain?.path == "/x/Brain")
        #expect(state.brainPath == "/x/Brain")
        #expect(state.brainURL?.path == "/x/Brain")
        // The compatibility setter replaces the default memory's folder and keeps the others.
        state.brainPath = "/y/Brain"
        #expect(state.brains.map(\.path) == ["/y/Brain", "/x/Brain-work"])
        #expect(state.brains.first?.name == "Shared")
        var empty = AppState(machineID: "m")
        #expect(empty.brainPath == nil && empty.defaultBrain == nil)
        empty.brainPath = "/z/Brain"
        #expect(empty.brains == [MemoryFolder(id: "shared", name: "Shared", path: "/z/Brain")])
    }

    /// The menu bar icon is on unless the person turned it off: a file written before the setting existed keeps it on,
    /// and off survives a save, so the command line never turns it back on.
    @Test func menuBarIconDefaultsOnAndRoundTrips() throws {
        #expect(AppState().menuBarIcon)
        let older = #"{"schemaVersion": 2, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#
        let decoded = try JSONDecoder().decode(AppState.self, from: Data(older.utf8))
        #expect(decoded.menuBarIcon)
        var state = AppState(machineID: "m")
        state.menuBarIcon = false
        let data = try JSONEncoder().encode(state)
        #expect(String(decoding: data, as: UTF8.self).contains("\"menuBarIcon\":false"))
        #expect(try JSONDecoder().decode(AppState.self, from: data).menuBarIcon == false)
        #expect(String(decoding: try JSONEncoder().encode(AppState(machineID: "m")), as: UTF8.self).contains("\"menuBarIcon\":true"))
    }

    /// The Obsidian vault the graph shows is remembered by its folder; an older file, or none chosen, shows the memory.
    @Test func theGraphsVaultRoundTrips() throws {
        #expect(AppState().graphVault == nil)
        let older = #"{"schemaVersion": 2, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#
        #expect(try JSONDecoder().decode(AppState.self, from: Data(older.utf8)).graphVault == nil)
        var state = AppState(machineID: "m")
        state.graphVault = "/Users/x/Documents/Notes Vault"
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data).graphVault == "/Users/x/Documents/Notes Vault")
        #expect(!String(decoding: try JSONEncoder().encode(AppState(machineID: "m")), as: UTF8.self).contains("graphVault"))
    }

    /// The memory the graph shows is remembered by its id, like the vault; an older file, or none chosen, shows the default.
    @Test func theGraphsMemoryRoundTrips() throws {
        #expect(AppState().graphMemory == nil)
        let older = #"{"schemaVersion": 2, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#
        #expect(try JSONDecoder().decode(AppState.self, from: Data(older.utf8)).graphMemory == nil)
        var state = AppState(machineID: "m")
        state.graphMemory = "work"
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data).graphMemory == "work")
        #expect(!String(decoding: try JSONEncoder().encode(AppState(machineID: "m")), as: UTF8.self).contains("graphMemory"))
    }

    /// "Save my own edits" is on unless the person turned it off: a file written before the setting existed keeps it on,
    /// and off survives a save, so the command line never turns it back on.
    @Test func savingYourOwnEditsDefaultsOnAndRoundTrips() throws {
        #expect(AppState().saveOwnEdits)
        let older = #"{"schemaVersion": 2, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#
        #expect(try JSONDecoder().decode(AppState.self, from: Data(older.utf8)).saveOwnEdits)
        var state = AppState(machineID: "m")
        state.saveOwnEdits = false
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data).saveOwnEdits == false)
    }

    /// Claude Code sessions of any account: in a terminal, or under a Claude window's Code tab.
    @Test func aClaudeCodeSessionIsSeenWhereverItRuns() {
        let idle = ProcessMonitor.snapshot(psOutput: """
        100 1 900000 /Applications/Claude.app/Contents/MacOS/Claude
        101 100 1000 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
        200 1 500 /bin/zsh -l
        """)
        #expect(!idle.hasClaudeCodeSession)
        let terminal = ProcessMonitor.snapshot(psOutput: "300 200 5000 claude --resume\n")
        #expect(terminal.hasClaudeCodeSession)
        let codeTab = ProcessMonitor.snapshot(psOutput: """
        100 1 900000 /Applications/Claude.app/Contents/MacOS/Claude
        150 100 5000 /Users/r/Library/Application Support/Claude/claude-code/2.1.0/claude --output-format stream-json
        """)
        #expect(codeTab.hasClaudeCodeSession)
    }
}
