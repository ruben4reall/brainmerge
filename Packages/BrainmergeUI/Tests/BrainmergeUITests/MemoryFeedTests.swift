import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct MemoryFeedTests {
    let client = Identity(slug: "client", name: "ClientStudio", tint: .blue)
    let ruben = Identity(slug: "ruben", name: "Ruben", tint: .orange, isPrimary: true)

    func entry(_ email: String, _ files: [String], date: Date = Date()) -> BrainGit.Entry {
        BrainGit.Entry(hash: UUID().uuidString, date: date, authorName: "x", authorEmail: email, message: "Brain update", files: files)
    }

    @Test func sentencesInPlainWords() {
        #expect(MemoryFeed.sentence(files: ["memory/atelier/decision_prix.md"], project: "atelier") == "remembered something about atelier")
        #expect(MemoryFeed.sentence(files: ["memory/trailbook/MEMORY.md"], project: "trailbook") == "updated its notes about trailbook")
        #expect(MemoryFeed.sentence(files: ["memory/trailbook/MEMORY.md", "memory/trailbook/feedback_tests.md"], project: "trailbook") == "updated 2 notes about trailbook")
        #expect(MemoryFeed.sentence(files: ["memory/a/x.md", "memory/b/y.md"], project: nil) == "updated 2 notes across 2 projects")
        #expect(MemoryFeed.sentence(files: ["BRAIN.md"], project: nil) == "changed the memory's instructions")
    }

    @Test func eventsCarryTheIdentity() {
        let events = MemoryFeed.events(from: [entry("client@brainmerge.local", ["memory/atelier/decision_prix.md"]), entry("nobody@example.com", ["x.md"])],
                                       identities: [client, ruben])
        #expect(events.count == 2)
        #expect(events[0].name == "ClientStudio" && events[0].tint == .blue && events[0].sentence == "remembered something about atelier")
        #expect(events[0].detail == "atelier · decision_prix.md")
        // An author outside Brainmerge (an Obsidian vault already under version control) keeps their git name.
        #expect(events[1].name == "x" && events[1].tint == .gray)
    }

    @Test func rootNotesAndNamelessAuthors() {
        #expect(MemoryFeed.sentence(files: ["memory/notes.md"], project: nil) == "updated 1 note")
        #expect(MemoryFeed.sentence(files: ["memory/a.md", "memory/b.md"], project: nil) == "updated 2 notes")
        let nameless = BrainGit.Entry(hash: "h", date: Date(), authorName: "", authorEmail: "nobody@example.com", message: "m", files: ["x.md"])
        #expect(MemoryFeed.events(from: [nameless], identities: []).first?.name == "Someone")
        #expect(MemoryFeed.events(from: [nameless], identities: []).first?.detail == "x.md")
    }

    @Test func countsPerAccount() {
        let counts = MemoryFeed.counts([entry("client@brainmerge.local", ["a"]), entry("client@brainmerge.local", ["b"]), entry("ruben@brainmerge.local", ["c"])])
        #expect(counts == ["client": 2, "ruben": 1])
    }
}
