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
}
