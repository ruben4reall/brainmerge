import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// What starts each state change's beat: the model dates only what it really saw happen, so a screen opened later finds
/// every beat over and draws its end.
@MainActor @Suite struct StateTriggersTests {
    typealias Clock = CreatureStampsTests.Clock
    typealias Processes = CreatureStampsTests.Processes

    func model(_ e: ManagerEnv, clock: Clock, processes: Processes = Processes()) -> AppModel {
        CreatureStampsTests().model(e, clock: clock, processes: processes)
    }

    /// The card's sage ring: only an account that was opening and now runs, never one started elsewhere or timed out.
    @Test func anAccountRingsOnlyWhenItWasOpening() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let clock = Clock(), processes = Processes()
        let m = model(e, clock: clock, processes: processes)
        await m.launch(minimum: .zero)
        let running = "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)\n"
        // Started outside Brainmerge: open, but it was never opening here.
        processes.output = running
        m.reload()
        #expect(m.accounts.first { $0.id == "work" }?.isRunning == true)
        #expect(m.openedAt.isEmpty)
        processes.output = ""
        m.reload()
        // Opened from Brainmerge: dated the moment it was seen running.
        m.markOpening("work")
        clock.advance(2)
        processes.output = running
        m.reload()
        #expect(m.openedAt == ["work": clock.now])
        // Quit, then an opening that times out: no new date.
        processes.output = ""
        clock.advance(2)
        m.reload()
        let opened = m.openedAt["work"]
        m.markOpening("work", fallback: .milliseconds(20))
        for _ in 0..<500 where !m.opening.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.opening.isEmpty)
        #expect(m.openedAt["work"] == opened)
    }

    /// A card added while the app runs rings around its orb; the accounts of the first load never do.
    @Test func onlyAnAccountAddedWhileTheAppRunsIsDated() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let clock = Clock()
        let m = model(e, clock: clock)
        await m.launch(minimum: .zero)
        #expect(m.accounts.count == 1 && m.addedAt.isEmpty)
        clock.advance(3)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Studio"))
        m.reload()
        #expect(m.addedAt == ["studio": clock.now])
        // Removed: its date goes with it.
        try e.manager.remove(slug: "studio", deleteData: true)
        m.reload()
        #expect(m.addedAt.isEmpty)
    }

    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    func assistant(id: String, output: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(Date().formatted(Self.iso))\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-fable-5-1\",\"usage\":{\"input_tokens\":1,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":10,\"output_tokens\":\(output)}}}\n"
    }

    /// The Usage cards come in once, when the first read replaces the placeholder; a later read updates them in place.
    @Test func usageArrivesOnlyWhenThePlaceholderGoes() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        let project = e.primaryProfile.projectsDir.appending(path: "-Users-me-atelier", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(assistant(id: "a", output: 120).utf8).write(to: project.appending(path: "s.jsonl"))
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        #expect(m.usage.isEmpty && m.usageArrivedAt == nil)
        await m.refreshUsage()
        #expect(!m.usage.isEmpty)
        #expect(m.usageArrivedAt == clock.now)
        let arrived = m.usageArrivedAt
        clock.advance(60)
        try Data((assistant(id: "a", output: 120) + assistant(id: "b", output: 30)).utf8).write(to: project.appending(path: "s.jsonl"))
        await m.refreshUsage()
        #expect(m.usage.first?.summary.todayOutput == 150)
        #expect(m.usageArrivedAt == arrived)
        #expect(AppModel.usageArrives(from: [], to: m.usage) && !AppModel.usageArrives(from: m.usage, to: m.usage))
        #expect(!AppModel.usageArrives(from: [], to: []))
    }

    func save(_ e: ManagerEnv, _ name: String) throws {
        try Data("# \(name)\n".utf8).write(to: e.brain.root.appending(path: "\(name).md"))
        try BrainGit(brain: e.brain).commitAll(authorName: "Personal", authorEmail: "personal@brainmerge.local", message: "Brain update by Personal")
    }

    /// A new save lands at the top of the timeline and is dated; the first read and another memory's rows never are.
    @Test func onlyNewSavesAreNewRows() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        try save(e, "first")
        let clock = Clock()
        let m = model(e, clock: clock)
        m.reload()
        m.refreshMemory()
        #expect(!m.memoryEvents.isEmpty && m.memoryArrivals.isEmpty)
        try save(e, "second")
        clock.advance(10)
        m.refreshMemory()
        let top = try #require(m.memoryEvents.first?.id)
        #expect(m.memoryArrivals == [top: clock.now])
        // Read again ten seconds later with nothing new: the highlight is long over, so its date is dropped.
        clock.advance(10)
        m.refreshMemory()
        #expect(m.memoryArrivals.isEmpty)
        // Another memory: its rows are not new saves.
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let workBrain = Brain(root: work.url)
        try Data("# w\n".utf8).write(to: workBrain.root.appending(path: "w.md"))
        try BrainGit(brain: workBrain).commitAll(authorName: "Work", authorEmail: "work@brainmerge.local", message: "Brain update by Work")
        m.reload()
        clock.advance(10)
        m.selectedBrainID = work.id
        #expect(m.memoryArrivals.isEmpty)
    }

    @Test func newRowsAreTheOnesAboveTheLastTopRow() {
        #expect(MemoryFeed.arrivals(from: [], to: ["c", "b", "a"]) == [])
        #expect(MemoryFeed.arrivals(from: ["b", "a"], to: ["d", "c", "b", "a"]) == ["d", "c"])
        #expect(MemoryFeed.arrivals(from: ["b", "a"], to: ["b", "a"]) == [])
        // Nothing shared: another memory, or a history rewritten; no row is new.
        #expect(MemoryFeed.arrivals(from: ["b", "a"], to: ["y", "x"]) == [])
    }
}
