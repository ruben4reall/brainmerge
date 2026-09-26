import Foundation
import Testing
@testable import BrainmergeCore

/// The words of a save, the same in `git log` (written by the command line) and on the Memory screen.
@Suite struct MemorySentenceTests {
    @Test func whatAnAccountRemembers() {
        #expect(MemorySentence.sentence(files: ["memory/atelier/decision_prix.md"]) == "remembered something about atelier")
        #expect(MemorySentence.sentence(files: ["memory/trailbook/MEMORY.md"]) == "updated its notes about trailbook")
        #expect(MemorySentence.sentence(files: ["memory/a/x.md", "memory/b/y.md"]) == "updated 2 notes across 2 projects")
        #expect(MemorySentence.sentence(files: ["memory/notes.md"]) == "updated 1 note")
        #expect(MemorySentence.sentence(files: ["memory/a.md", "memory/b.md"]) == "updated 2 notes")
        #expect(MemorySentence.sentence(files: ["BRAIN.md"]) == "changed the memory's instructions")
        #expect(MemorySentence.sentence(files: [".brainmerge/projects.json"]) == "updated 1 file")
    }

    /// A project's index (its MEMORY.md) changes with the notes it lists: it is never counted as one more note or one more
    /// thing remembered. Alone, it is still said ("updated its notes about").
    @Test func anIndexIsNeverCountedAsANote() {
        #expect(MemorySentence.sentence(files: ["memory/acme/MEMORY.md", "memory/acme/deploy.md"]) == "remembered something about acme")
        #expect(MemorySentence.sentence(files: ["memory/acme/MEMORY.md", "memory/acme/deploy.md", "memory/acme/stack.md"]) == "remembered 2 things about acme")
        #expect(MemorySentence.sentence(files: ["memory/a/MEMORY.md", "memory/a/x.md", "memory/b/MEMORY.md", "memory/b/y.md", "memory/b/z.md"])
                == "updated 3 notes across 2 projects")
        // The index of one project and a note of another: the save is about that note's project.
        #expect(MemorySentence.sentence(files: ["memory/a/MEMORY.md", "memory/b/y.md"]) == "remembered something about b")
        // Only indexes: they are what changed.
        #expect(MemorySentence.sentence(files: ["memory/a/MEMORY.md", "memory/b/MEMORY.md"]) == "updated 2 notes across 2 projects")
        #expect(MemorySentence.sentence(files: ["memory/acme/MEMORY.md", "memory/acme/deploy.md"], byYou: true) == "edited a note about acme")
        #expect(MemorySentence.message(name: "Work", files: ["memory/acme/MEMORY.md", "memory/acme/deploy.md"]) == "Work remembered something about acme")
    }

    /// What the person changed in the notes themselves, outside Claude.
    @Test func whatYouEdited() {
        #expect(MemorySentence.sentence(files: ["memory/acme/deploy.md"], byYou: true) == "edited a note about acme")
        #expect(MemorySentence.sentence(files: ["memory/acme/stack.md", "memory/acme/deploy.md"], byYou: true) == "edited 2 notes about acme")
        #expect(MemorySentence.sentence(files: ["memory/a/x.md", "memory/b/y.md"], byYou: true) == "edited 2 notes across 2 projects")
        #expect(MemorySentence.sentence(files: ["memory/notes.md"], byYou: true) == "edited 1 note")
        #expect(MemorySentence.sentence(files: ["BRAIN.md"], byYou: true) == "edited the memory's instructions")
        #expect(MemorySentence.sentence(files: [".gitignore", ".brainmerge/projects.json"], byYou: true) == "edited 2 files")
    }

    @Test func theCommitMessageIsTheNameAndTheSentence() {
        #expect(MemorySentence.message(name: "Work", files: ["memory/acme/a.md", "memory/acme/b.md"]) == "Work remembered 2 things about acme")
        #expect(MemorySentence.message(name: "You", files: ["memory/acme/a.md", "memory/acme/b.md"], byYou: true) == "You edited 2 notes about acme")
    }

    @Test func aNoteBelongsToTheProjectFolderItIsIn() {
        #expect(MemorySentence.project(of: "memory/acme/deploy.md") == "acme")
        #expect(MemorySentence.project(of: "memory/deploy.md") == nil)
        #expect(MemorySentence.project(of: "BRAIN.md") == nil)
        #expect(MemorySentence.project(files: ["memory/acme/a.md", "memory/acme/b.md"]) == "acme")
        #expect(MemorySentence.project(files: ["memory/acme/a.md", "memory/kayak/b.md"]) == nil)
    }
}
