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

    @Test func saveKeepsThePreviousCopy() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try store.save(AppState(machineID: "first"))
        #expect(!FileManager.default.fileExists(atPath: store.previousFile.path))
        try store.save(AppState(machineID: "second"))
        let previous = try JSONDecoder().decode([String: AnyCodableValue].self, from: Data(contentsOf: store.previousFile))
        #expect(previous["machineID"] == .string("first"))
        #expect(try store.load().machineID == "second")
    }

    /// A save over a damaged file keeps the good copy from before: the damaged one is not worth putting back.
    @Test func aDamagedFileNeverReplacesTheGoodPreviousCopy() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try store.save(AppState(machineID: "good"))
        try store.save(AppState(machineID: "later"))
        try Data("{ broken".utf8).write(to: home.paths.stateFile)
        try store.save(AppState(machineID: "fresh"))
        let previous = try? JSONDecoder().decode([String: AnyCodableValue].self, from: Data(contentsOf: store.previousFile))
        #expect(previous?["machineID"] == .string("good"))
        #expect(try store.load().machineID == "fresh")
    }

    @Test func aDamagedFileIsNeverAFreshState() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try FileManager.default.createDirectory(at: home.paths.appSupport, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: home.paths.stateFile)
        #expect(throws: BrainmergeError.stateDamaged) { try store.load() }
    }

    @Test func restoringThePreviousCopyBringsItBack() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try store.save(AppState(machineID: "good"))
        try store.save(AppState(machineID: "later"))
        try Data("{ broken".utf8).write(to: home.paths.stateFile)
        #expect(store.canRestorePrevious)
        try store.restorePrevious()
        #expect(try store.load().machineID == "good")
    }

    @Test func onlyACopyThisVersionCanReadIsOfferedBack() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        #expect(!store.canRestorePrevious)
        try store.save(AppState(machineID: "good"))
        try store.save(AppState(machineID: "later"))
        #expect(store.canRestorePrevious)
        try Data("{ broken".utf8).write(to: store.previousFile)
        #expect(!store.canRestorePrevious)
        // Written by a newer Brainmerge too: putting it back would only show the same screen again.
        try Data(#"{"schemaVersion": 99, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#.utf8)
            .write(to: store.previousFile)
        #expect(!store.canRestorePrevious)
    }

    @Test func anUnreadablePreviousCopyIsNeverPutBack() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try store.save(AppState(machineID: "good"))
        try store.save(AppState(machineID: "later"))
        try Data("{ broken".utf8).write(to: home.paths.stateFile)
        try Data("{ also broken".utf8).write(to: store.previousFile)
        #expect(throws: BrainmergeError.stateDamaged) { try store.restorePrevious() }
        #expect(try Data(contentsOf: home.paths.stateFile) == Data("{ broken".utf8))
    }

    @Test func restoringWaitsForTheLock() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = StateStore(paths: home.paths)
        try store.save(AppState(machineID: "good"))
        try store.save(AppState(machineID: "later"))
        try Data("{ broken".utf8).write(to: home.paths.stateFile)
        // The command line holds the lock through its own change: the restore waits for it, never writes in between.
        let held = try StateStore(paths: home.paths).lock()
        let paths = home.paths
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? StateStore(paths: paths).restorePrevious()
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 0.3) == .timedOut)
        #expect(throws: BrainmergeError.stateDamaged) { try store.load() }
        held.release()
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(try store.load().machineID == "good")
    }

    @Test func aDamagedStateSaysWhereToTurn() {
        #expect(BrainmergeError.stateDamaged.description
                == "state.json can't be read. Open Brainmerge to put back the copy from before your last change, when there is one.")
    }

    @Test func concurrentUpdatesBothLand() async throws {
        let home = try TempHome(); defer { home.remove() }
        try StateStore(paths: home.paths).save(AppState(machineID: "m"))
        let paths = home.paths
        await withTaskGroup(of: Void.self) { group in
            for slug in ["one", "two", "three", "four"] {
                group.addTask {
                    // A separate store each time: a separate descriptor on the lock, like the app and the command line.
                    try? StateStore(paths: paths).update { state in
                        // Read, wait, write: without the lock, another update would land in between and be lost.
                        usleep(50_000)
                        state.identities.append(Identity(slug: slug, name: slug.capitalized))
                    }
                }
            }
        }
        #expect(Set(try StateStore(paths: paths).load().identities.map(\.slug)) == ["one", "two", "three", "four"])
    }
}

/// Reads one JSON field without the app's own decoder.
enum AnyCodableValue: Decodable, Equatable {
    case string(String), other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) } else { self = .other }
    }
}
