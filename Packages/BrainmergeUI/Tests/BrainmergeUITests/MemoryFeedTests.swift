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

    /// The words are the command line's (MemorySentence), whatever the commit's own message says: older saves read well too.
    @Test func sentencesInPlainWords() {
        let events = MemoryFeed.events(from: [entry("client@brainmerge.local", ["memory/trailbook/MEMORY.md", "memory/trailbook/feedback_tests.md"]),
                                              entry("client@brainmerge.local", ["BRAIN.md"])], identities: [client])
        #expect(events.map(\.sentence) == ["remembered 2 things about trailbook", "changed the memory's instructions"])
    }

    /// The person's own edits, saved by the app: "You", in gray, and never counted as an account's saves.
    @Test func yourOwnEditsReadYouInGray() {
        let events = MemoryFeed.events(from: [entry(OwnEdits.author.email, ["memory/acme/a.md", "memory/acme/b.md"])], identities: [client, ruben])
        #expect(events.first?.name == "You" && events.first?.tint == .gray && events.first?.slug == nil)
        #expect(events.first?.sentence == "edited 2 notes about acme")
        #expect(MemoryFeed.counts([entry(OwnEdits.author.email, ["a"]), entry("client@brainmerge.local", ["b"])]) == ["client": 1])
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
        let nameless = BrainGit.Entry(hash: "h", date: Date(), authorName: "", authorEmail: "nobody@example.com", message: "m", files: ["x.md"])
        #expect(MemoryFeed.events(from: [nameless], identities: []).first?.name == "Someone")
        #expect(MemoryFeed.events(from: [nameless], identities: []).first?.detail == "x.md")
    }

    @Test func countsPerAccount() {
        let counts = MemoryFeed.counts([entry("client@brainmerge.local", ["a"]), entry("client@brainmerge.local", ["b"]), entry("ruben@brainmerge.local", ["c"])])
        #expect(counts == ["client": 2, "ruben": 1])
    }
}
