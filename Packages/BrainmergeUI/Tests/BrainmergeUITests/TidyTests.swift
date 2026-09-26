import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The Memory screen's third tab, Tidy: its count on the tab, what it read from the selected memory, and its buttons, each
/// one click that says what it did in the timeline, or why it did nothing.
@MainActor @Suite struct TidyTests {
    static let scratch = "scratch-2026-09-23-5050ce"

    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.environment = [:]
        return model
    }

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Two beehive notes left in a quick session's folder, an empty quick session folder, a copy left in acme, all saved an
    /// hour ago.
    func memory(_ e: ManagerEnv) throws -> BrainGit {
        let brain = e.brain
        try write("- [Pricing](beehive-pricing.md)\n- [Gear](beehive-gear.md)\n", "memory/\(Self.scratch)/MEMORY.md", in: brain)
        try write("# pricing\n", "memory/\(Self.scratch)/beehive-pricing.md", in: brain)
        try write("# gear\n", "memory/\(Self.scratch)/beehive-gear.md", in: brain)
        try write("- [[route]]\n", "memory/beehive/MEMORY.md", in: brain)
        try write("# route\n", "memory/beehive/route.md", in: brain)
        try write("- [Deploy](deploy.md)\n", "memory/acme/MEMORY.md", in: brain)
        try write("# deploy\n", "memory/acme/deploy.md", in: brain)
        try write("# deploy, Perso's\n", "memory/acme/deploy.perso.md", in: brain)
        try FileManager.default.createDirectory(at: brain.memoryDir(forProject: "scratch-2026-09-10-5855fd"), withIntermediateDirectories: true)
        let git = BrainGit(brain: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        let fm = FileManager.default
        let walk = try #require(fm.enumerator(atPath: brain.root.path))
        while let path = walk.nextObject() as? String {
            if path == ".git" { walk.skipDescendants(); continue }
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: brain.root.appending(path: path).path)
        }
        return git
    }

    func setUp() throws -> (ManagerEnv, AppModel, BrainGit) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Perso")
        let git = try memory(e)
        let m = model(e)
        m.reload()
        return (e, m, git)
    }

    @Test func theTabSaysHowManyRowsItHas() {
        #expect(MemoryView.Mode.allCases.map(\.rawValue) == ["Graph", "Timeline", "Tidy"])
        #expect(MemoryView.title(of: .tidy, tidyCount: 4) == "Tidy (4)")
        #expect(MemoryView.title(of: .tidy, tidyCount: 0) == "Tidy")
        #expect(MemoryView.title(of: .graph, tidyCount: 4) == "Graph")
        #expect(MemoryTidyView.tidy == "Nothing to tidy. Every note is where the next session will find it.")
    }

    @Test func theTabReadsTheSelectedMemory() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        #expect(m.memoryTidy.report == nil && m.memoryTidy.count == 0)
        await m.refreshTidy()
        let report = try #require(m.memoryTidy.report)
        #expect(report.groups.map(\.id) == [.oneOff, .copies])
        #expect(m.memoryTidy.count == 3)
        #expect(report.groups[0].items.first?.suggested == ["beehive"])
        // The account's copy is known by its slug.
        #expect(report.groups[1].items.first?.sentence == "acme has two copies of deploy.md.")
    }

    /// The preview says what will move and moves nothing; Move makes one commit, which the timeline says as yours.
    @Test func fileUnderPreviewsThenMovesOnClick() async throws {
        let (e, m, git) = try setUp(); defer { e.home.remove() }
        await m.refreshTidy()
        let plan = try #require(await m.planFiling(Self.scratch, under: "beehive"))
        #expect(plan.preview == "Move 2 notes from \(Self.scratch) to beehive, with their index lines.")
        #expect(try git.log(limit: 10).count == 1)

        await m.file(plan)
        #expect(m.message == nil)
        #expect(FileManager.default.fileExists(atPath: e.brain.root.appending(path: "memory/beehive/beehive-gear.md").path))
        let event = try #require(m.memoryEvents.first)
        #expect(event.name == "You" && event.sentence == "filed 2 notes under beehive" && event.tint == .gray)
        // The folder is empty now: it joins the empty ones, still there.
        #expect(m.memoryTidy.report?.groups.first?.items.map(\.sentence) == ["2 quick session folders are empty."])
    }

    /// A refusal says why, and nothing moved.
    @Test func aNoteBeingWrittenIsSaidAndStays() async throws {
        let (e, m, git) = try setUp(); defer { e.home.remove() }
        let plan = try #require(await m.planFiling(Self.scratch, under: "beehive"))
        try FileManager.default.setAttributes([.modificationDate: Date()],
                                              ofItemAtPath: e.brain.root.appending(path: "memory/\(Self.scratch)/beehive-gear.md").path)
        await m.file(plan)
        #expect(m.message?.title == "Nothing was moved")
        #expect(m.message?.detail == "This note is being written. Try again in a moment.")
        #expect(try git.log(limit: 10).count == 1)
        #expect(AppModel.sentence(for: BrainmergeError.noteNotSaved).detail
                == "This note has changes that are not saved yet. Try again once they are saved.")
        #expect(AppModel.sentence(for: BrainmergeError.noteExists(name: "a.md", project: "acme")).detail == "There is already a note called a.md in acme.")
    }

    /// Compare reads both copies, from inside the memory only; Keep this one archives the other.
    @Test func compareThenKeepOne() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.refreshTidy()
        let item = try #require(m.memoryTidy.report?.groups.first { $0.id == .copies }?.items.first)
        let copies = await m.readCopies(item)
        #expect(copies.map(\.name) == ["deploy.md", "deploy.perso.md"])
        #expect(copies.map(\.text) == ["# deploy\n", "# deploy, Perso's\n"])
        await m.keep("memory/acme/deploy.perso.md", over: "memory/acme/deploy.md")
        #expect(m.message == nil)
        #expect(m.memoryEvents.first?.sentence == "kept one copy of deploy.md")
        #expect(try String(contentsOf: e.brain.root.appending(path: "memory/acme/deploy.md"), encoding: .utf8) == "# deploy, Perso's\n")
        #expect(m.memoryTidy.report?.groups.contains { $0.id == .copies } == false)
    }

    @Test func hideHidesTheEmptyFolders() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        try FileManager.default.createDirectory(at: e.brain.memoryDir(forProject: "scratch-2026-09-11-343e32"), withIntermediateDirectories: true)
        await m.refreshTidy()
        let item = try #require(m.memoryTidy.report?.groups.first { $0.id == .oneOff }?.items.first { $0.kind == .emptyOneOffFolders })
        #expect(item.sentence == "2 quick session folders are empty.")
        await m.hideEmptyFolders(item)
        #expect(m.memoryEvents.first?.sentence == "hid 2 empty folders from Tidy")
        #expect(m.memoryTidy.report?.groups.first { $0.id == .oneOff }?.items.map(\.kind) == [.oneOffNotes])
        #expect(FileManager.default.fileExists(atPath: e.brain.memoryDir(forProject: "scratch-2026-09-11-343e32").path))
    }
}
