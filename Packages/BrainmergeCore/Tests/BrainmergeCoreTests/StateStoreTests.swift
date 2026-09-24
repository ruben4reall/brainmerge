import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct StateStoreTests {
    @Test func missingFileGivesDefaultState() throws {
        let home = try TempHome(); defer { home.remove() }
        let state = try StateStore(paths: home.paths).load()
        #expect(state.identities.isEmpty)
        #expect(state.brainPath == nil)
        #expect(state.schemaVersion == AppState.currentSchema)
        #expect(!state.machineID.isEmpty)
    }

    @Test func roundTrip() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        var state = AppState()
        state.brainPath = home.url.appending(path: "Brain").path
        state.identities = [Identity(slug: "perso", name: "Perso", isPrimary: true)]
        try store.save(state)
        let loaded = try store.load()
        #expect(loaded.brainPath == state.brainPath)
        #expect(loaded.identities.map(\.slug) == ["perso"])
        #expect(loaded.primary?.name == "Perso")
        #expect(loaded.identity(slug: "perso")?.isPrimary == true)
        #expect(loaded.machineID == state.machineID)
    }

    @Test func notesAppIsSavedAndOldStatesStillLoad() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        var state = AppState(machineID: "m")
        state.notesApp = "md.obsidian"
        try store.save(state)
        #expect(try store.load().notesApp == "md.obsidian")
        // A state written before the setting existed: the key is simply absent.
        let old = #"{"schemaVersion":1,"machineID":"m","identities":[],"autoRebuild":true,"brainLanguage":"en"}"#
        try FileManager.default.createDirectory(at: home.paths.stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(old.utf8).write(to: home.paths.stateFile)
        #expect(try store.load().notesApp == nil)
    }

    @Test func schemaOneStatesGetASharedMemory() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try FileManager.default.createDirectory(at: home.paths.appSupport, withIntermediateDirectories: true)
        // Every 0.2 user: one brainPath, no list of memories.
        let old = #"{"schemaVersion":1,"machineID":"m","brainPath":"/x/Brain","identities":[{"id":"6F5E1B70-0000-4000-8000-000000000001","slug":"perso","name":"Perso","tint":"orange","isPrimary":true,"surfaces":{"desktop":true,"cli":true},"iconMode":"launcher","sharedHistory":false,"createdAt":"2026-09-24T10:00:00Z"}],"autoRebuild":true,"brainLanguage":"en"}"#
        try Data(old.utf8).write(to: home.paths.stateFile)
        let state = try store.load()
        #expect(state.schemaVersion == AppState.currentSchema)
        #expect(state.brains == [MemoryFolder(id: "shared", name: "Shared", path: "/x/Brain")])
        #expect(state.brainPath == "/x/Brain")
        #expect(state.identities.first?.brain == nil)
        #expect(state.brain(for: state.identities[0])?.id == "shared")
        // Saved again: the list is written, and read back as is, with a second memory and an identity attached to it.
        var next = state
        next.brains.append(MemoryFolder(id: "work", name: "Work", path: "/x/Brain-work"))
        next.identities[0].brain = "work"
        try store.save(next)
        let reloaded = try store.load()
        #expect(reloaded.brains.map(\.id) == ["shared", "work"])
        #expect(reloaded.identities[0].brain == "work")
        #expect(reloaded.brainPath == "/x/Brain")
        let json = try String(contentsOf: home.paths.stateFile, encoding: .utf8)
        #expect(json.contains("\"brains\"") && json.contains("\"brainPath\" : \"/x/Brain\""))
    }

    @Test func newerSchemaIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try FileManager.default.createDirectory(at: home.paths.appSupport, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 99, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#.utf8)
            .write(to: home.paths.stateFile)
        #expect(throws: BrainmergeError.stateTooNew(99)) { try store.load() }
    }
}
