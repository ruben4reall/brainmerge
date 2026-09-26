import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct BrainTests {
    @Test func initializeCreatesLayoutAndGit() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .fr)
        #expect(brain.isInitialized)
        #expect(try String(contentsOf: brain.brainMD, encoding: .utf8).hasPrefix("# Cerveau partagé"))
        #expect(FileManager.default.fileExists(atPath: brain.memoryDir.path))
        #expect(try String(contentsOf: brain.projectsFile, encoding: .utf8) == "{}\n")
        #expect(try String(contentsOf: brain.gitignore, encoding: .utf8).contains(".brainmerge/lock"))
        #expect(FileManager.default.fileExists(atPath: brain.gitDir.path))
        #expect(brain.memoryDir(forProject: "atelier").path.hasSuffix("Brain/memory/atelier"))
    }

    @Test func initializeIsIdempotentAndKeepsExistingFiles() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Mine\n".utf8).write(to: root.appending(path: "BRAIN.md"))
        try Data("note\n".utf8).write(to: root.appending(path: "Journal.md"))
        _ = try Brain.initialize(at: root, language: .en)
        let brain = try Brain.initialize(at: root, language: .en)
        #expect(try String(contentsOf: brain.brainMD, encoding: .utf8) == "# Mine\n")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Journal.md").path))
    }

    /// Each account's list of what it wrote stays out of the history: a new memory ignores it from the start, an existing
    /// one gets the line appended, and nothing the person wrote in the file is changed.
    @Test func theLedgersAreIgnoredInNewAndExistingMemories() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        #expect(try String(contentsOf: brain.gitignore, encoding: .utf8) == ".DS_Store\n.brainmerge/lock\n.brainmerge/touched/\n")
        try brain.ensureIgnores()
        #expect(try String(contentsOf: brain.gitignore, encoding: .utf8) == ".DS_Store\n.brainmerge/lock\n.brainmerge/touched/\n")

        try Data(".DS_Store\n.brainmerge/lock\n# mine\n.trash".utf8).write(to: brain.gitignore)
        try brain.ensureIgnores()
        #expect(try String(contentsOf: brain.gitignore, encoding: .utf8) == ".DS_Store\n.brainmerge/lock\n# mine\n.trash\n.brainmerge/touched/\n")
        try brain.ensureIgnores()
        #expect(try String(contentsOf: brain.gitignore, encoding: .utf8) == ".DS_Store\n.brainmerge/lock\n# mine\n.trash\n.brainmerge/touched/\n")
    }

    /// A .gitignore that is a link (a shared memory can bring one pointing at ~/.ssh/config) is never written through,
    /// nor replaced: the file it points to stays exactly as it was. A broken link is left alone too.
    @Test func aLinkedGitignoreIsNeverWrittenThrough() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let outside = home.url.appending(path: "config")
        try Data("Host example\n".utf8).write(to: outside)
        try FileManager.default.removeItem(at: brain.gitignore)
        try FileManager.default.createSymbolicLink(at: brain.gitignore, withDestinationURL: outside)
        try brain.ensureIgnores()
        #expect(try String(contentsOf: outside, encoding: .utf8) == "Host example\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: brain.gitignore.path) == outside.path)
        try FileManager.default.removeItem(at: outside)
        try brain.ensureIgnores()
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: brain.gitignore.path) == outside.path)
    }

    /// A folder inside another repository would get a second repository of its own, and the outer one's backups would stop
    /// covering its notes: refused before anything is created, with the exact sentence. The repository's own top folder,
    /// or a memory that already has its history, is fine.
    @Test func aFolderInsideAnotherRepositoryIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let top = home.url.appending(path: "Projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: top.appending(path: ".git"), withIntermediateDirectories: true)
        let inside = top.appending(path: "notes/brain", directoryHint: .isDirectory)
        let real = top.resolvingSymlinksInPath().path
        #expect(Brain.enclosingRepository(of: inside)?.path == real)
        #expect(Brain.enclosingRepository(of: top) == nil)
        #expect(Brain.enclosingRepository(of: home.url.appending(path: "Brain")) == nil)
        do {
            _ = try Brain.initialize(at: inside, language: .en)
            Issue.record("a folder inside another repository must be refused")
        } catch let error as BrainmergeError {
            #expect(error == .memoryInsideRepository(real))
            #expect(error.description == "This folder is inside another git repository (\(real)). Brainmerge would create a second repository inside it, and that repository's backups would stop covering these notes. Choose the repository's top folder, or a folder outside it.")
        }
        #expect(!FileManager.default.fileExists(atPath: inside.path))

        // Reached through a link: the folder is judged where it really is.
        let link = home.url.appending(path: "Shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: top)
        #expect(Brain.enclosingRepository(of: link.appending(path: "notes"))?.path == real)

        // A memory that already has its own history is left as it is, wherever it sits.
        let existing = top.appending(path: "old", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existing.appending(path: ".git"), withIntermediateDirectories: true)
        #expect(throws: Never.self) { try Brain.initialize(at: existing, language: .en) }
    }

    @Test func templatesExistInBothLanguages() {
        #expect(BrainTemplates.brainMD(.en).contains("Never write secrets"))
        #expect(BrainTemplates.brainMD(.fr).contains("Ne jamais écrire de secret"))
    }
}
