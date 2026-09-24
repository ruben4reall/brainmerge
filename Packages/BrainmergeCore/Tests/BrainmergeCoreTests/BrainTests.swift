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

    @Test func templatesExistInBothLanguages() {
        #expect(BrainTemplates.brainMD(.en).contains("Never write secrets"))
        #expect(BrainTemplates.brainMD(.fr).contains("Ne jamais écrire de secret"))
    }
}
