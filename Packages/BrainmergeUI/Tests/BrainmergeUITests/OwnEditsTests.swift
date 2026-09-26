import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The person's own edits to the notes are saved as You by the app (never by a hook), on the minute clock, once quiet and
/// while no Claude Code session runs; the setting turns it off. A memory inside another repository is refused where it is chosen.
@MainActor @Suite struct OwnEditsTests {
    final class Processes: @unchecked Sendable {
        var ps = ""
    }

    func model(_ e: ManagerEnv, processes: Processes = Processes()) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { processes.ps }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        return model
    }

    func note(_ e: ManagerEnv, _ path: String) throws {
        let url = e.brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# mine\n".utf8).write(to: url)
    }

    @Test func yourEditsAreSavedAsYouOnceQuietAndNoSessionRuns() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        try note(e, "memory/acme/idea.md")
        try note(e, "Daily/2026-09-25.md")
        let processes = Processes()
        let m = model(e, processes: processes)
        m.reload()
        let later = Date().addingTimeInterval(OwnEdits.quietPeriod + 60)

        await m.saveOwnEditsIfQuiet(now: Date())?.value
        #expect(try BrainGit(brain: e.brain).log().isEmpty, "a change of the last ten minutes waits")
        processes.ps = "  300 200 5000 claude --resume\n"
        await m.saveOwnEditsIfQuiet(now: later)?.value
        #expect(try BrainGit(brain: e.brain).log().isEmpty, "a running Claude Code session may be writing notes")

        processes.ps = ""
        await m.saveOwnEditsIfQuiet(now: later)?.value
        let last = try #require(try BrainGit(brain: e.brain).log(limit: 1).first)
        #expect(last.authorName == "You" && last.authorEmail == OwnEdits.author.email)
        #expect(last.files.contains("memory/acme/idea.md") && !last.files.contains("Daily/2026-09-25.md"))
        #expect(m.memoryEvents.first?.name == "You", "the timeline shows it at once")
    }

    @Test func theSwitchOffLeavesYourEditsUnsaved() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        try note(e, "memory/acme/idea.md")
        let m = model(e)
        m.reload()
        #expect(m.saveOwnEdits)
        await m.setSaveOwnEdits(false).value
        #expect(try e.store.load().saveOwnEdits == false)
        #expect(m.saveOwnEditsIfQuiet(now: Date().addingTimeInterval(7200)) == nil)
        #expect(try BrainGit(brain: e.brain).log().isEmpty)
        m.reload()
        #expect(!m.saveOwnEdits)
        await m.setSaveOwnEdits(true).value
        #expect(try e.store.load().saveOwnEdits)
    }

    static func nestedSentence(_ top: URL) -> String {
        "This folder is inside another git repository (\(top.resolvingSymlinksInPath().path)). Brainmerge would create a second repository inside it, and that repository's backups would stop covering these notes. Choose the repository's top folder, or a folder outside it."
    }

    /// New memory: the sheet says why, as soon as the folder is chosen and again if Create is clicked anyway.
    @Test func newMemoryInsideAnotherRepositorySaysWhy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let top = e.home.url.appending(path: "code", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: top.appending(path: ".git"), withIntermediateDirectories: true)
        let m = model(e)
        m.reload()
        #expect(m.folderProblem(top.appending(path: "notes")) == Self.nestedSentence(top))
        #expect(m.folderProblem(top) == nil)
        #expect(m.folderProblem(e.home.url.appending(path: "Brain-work")) == nil)
        #expect(await m.addBrain(name: "Work", path: top.appending(path: "notes")) == nil)
        #expect(m.message?.detail == Self.nestedSentence(top))
        #expect(m.brains.count == 1)
    }

    /// Setup: "Continue" on the memory's step stays there and says why.
    @Test func setupRefusesAFolderInsideAnotherRepository() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false)
        let app = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        app.git = OnboardingModelTests.Tools(true).availability
        app.reload()
        let onboarding = OnboardingModel(app: app)
        let top = e.home.url.appending(path: "vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: top.appending(path: ".git"), withIntermediateDirectories: true)
        onboarding.step = .brainLocation
        onboarding.choice = .existing(top.appending(path: "Claude"))
        onboarding.continueFromLocation()
        #expect(onboarding.step == .brainLocation)
        #expect(onboarding.error?.detail == Self.nestedSentence(top))
        onboarding.choice = .existing(top)
        onboarding.continueFromLocation()
        #expect(onboarding.step == .adopt && onboarding.error == nil)
    }
}
