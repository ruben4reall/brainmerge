import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The Memory screen's banner for notes a save held back because they look like they hold a key: where, never the value,
/// and the two answers.
@MainActor @Suite struct HeldNotesTests {
    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        return model
    }

    /// A key built when the test runs: the repository never holds one.
    static var key: String { "gh" + "p_" + String(repeating: "Zq8Rk3Tn", count: 5).prefix(36) }

    func holdOne(_ e: ManagerEnv) throws -> HeldNote {
        let perso = try #require(try e.store.load().identity(slug: "perso"))
        let notes = e.brain.memoryDir(forProject: "acme-api")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Deploy\n\nPush with \(Self.key)\n".utf8).write(to: notes.appending(path: "deploy.md"))
        try TouchedLedger(brain: e.brain, slug: "perso").append("memory/acme-api/deploy.md")
        let git = BrainGit(brain: e.brain)
        let outcome = try AccountSave(brain: e.brain, git: git, held: HeldStore(paths: e.home.paths, memoryID: "shared")).run(for: perso)
        return try #require(outcome.held.first)
    }

    @Test func theBannerSaysWhereAndWhatNeverTheValue() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try holdOne(e)
        let m = model(e)
        m.reload()
        m.refreshMemory()
        #expect(m.heldNotes.count == 1)
        #expect(AppModel.heldSummary(m.heldNotes) == "1 note was not saved: it looks like it holds a key.")
        #expect(m.heldNotes.first?.sentence == "acme-api/deploy.md, line 3, looks like a GitHub token.")
        #expect(m.heldNoteURL(try #require(m.heldNotes.first))?.path == e.brain.memoryDir(forProject: "acme-api").appending(path: "deploy.md").path)
        let shown = String(describing: m.heldNotes) + (AppModel.heldSummary(m.heldNotes) ?? "") + m.heldNotes.map(\.sentence).joined()
            + String(describing: m.memoryEvents)
        #expect(!shown.contains(Self.key) && !shown.contains("Push with"))
        #expect(AppModel.heldSummary([]) == nil)
        let two = [HeldNote(account: "perso", path: "memory/a.md", line: 1, shape: .aws, hash: LineHash(line: "a")),
                   HeldNote(account: "perso", path: "memory/b.md", line: 1, shape: .aws, hash: LineHash(line: "b"))]
        #expect(AppModel.heldSummary(two) == "2 notes were not saved: they look like they hold keys.")
    }

    @Test func itIsNotASecretSavesItAtTheNextSave() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try holdOne(e)
        let m = model(e)
        m.reload()
        m.refreshMemory()
        await m.notASecret(try #require(m.heldNotes.first))
        #expect(m.heldNotes.isEmpty)
        #expect(NotSecrets.hashes(in: e.brain).count == 1)
        let perso = try #require(try e.store.load().identity(slug: "perso"))
        let saved = try AccountSave(brain: e.brain, git: BrainGit(brain: e.brain), held: HeldStore(paths: e.home.paths, memoryID: "shared")).run(for: perso)
        #expect(saved.saved == ["memory/acme-api/deploy.md"])
    }

    @Test func saveAnywayAllowsItOnce() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try holdOne(e)
        let m = model(e)
        m.reload()
        m.refreshMemory()
        await m.saveAnyway(try #require(m.heldNotes.first))
        #expect(m.heldNotes.isEmpty)
        #expect(HeldStore(paths: e.home.paths, memoryID: "shared").load().allowed.count == 1)
        #expect(NotSecrets.hashes(in: e.brain).isEmpty)
    }
}
