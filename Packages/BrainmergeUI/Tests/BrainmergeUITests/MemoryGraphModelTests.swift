import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct MemoryGraphModelTests {
    func brain(_ home: TempHome) throws -> Brain {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        try write(brain.root, "memory/website/MEMORY.md", "- [Pricing](decision_pricing.md)\n")
        try write(brain.root, "memory/website/decision_pricing.md", "---\nidentity: studio\n---\n# Pricing\n\nKeep the launch offer until October.\nSee [[project_launch]].\n")
        try write(brain.root, "memory/mobile-app/project_launch.md", "Ship in October.\n")
        try BrainGit(brain: brain).commitAll(authorName: "Studio", authorEmail: "studio@brainmerge.local", message: "Brain update by Studio")
        return brain
    }

    func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func refreshBuildsTheGraphAndKnowsWhoWroteEachNote() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        #expect(model.graph.node("memory/website/decision_pricing.md") != nil)
        #expect(model.graph.node("project:website") != nil)
        #expect(model.authors["memory/website/decision_pricing.md"]?.slug == "studio")
        #expect(model.authors["memory/website/decision_pricing.md"]?.name == "Studio")
        #expect(model.pulses.isEmpty)   // the first look does not flash everything
        #expect(model.neighbors(of: "memory/website/decision_pricing.md") == ["memory/mobile-app/project_launch.md", "project:website"])
        #expect(model.notes(savedBy: "studio").isSuperset(of: ["memory/website/decision_pricing.md", "project:website"]))
        #expect(!model.notes(savedBy: "studio").contains("BRAIN.md") || model.authors["BRAIN.md"]?.slug == "studio")
        #expect(model.layout.count == model.graph.nodes.count)
    }

    @Test func aNoteBeingWrittenThenSavedPulsesLive() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        // Claude Code writes a note: it appears and pulses, not attributed yet.
        try write(brain.root, "memory/website/feedback_tone.md", "Plain words.\n")
        await model.refresh(root: brain.root)
        #expect(model.graph.node("memory/website/feedback_tone.md") != nil)
        #expect(model.pulses["memory/website/feedback_tone.md"] != nil)
        #expect(model.pulses["memory/website/feedback_tone.md"]?.slug == nil)
        // The session ends, the hook saves it under the account's name: it pulses again, in that account's color.
        try BrainGit(brain: brain).commitAll(authorName: "Personal", authorEmail: "personal@brainmerge.local", message: "Brain update by Personal")
        model.clearPulses()
        await model.refresh(root: brain.root)
        #expect(model.pulses["memory/website/feedback_tone.md"]?.slug == "personal")
        #expect(model.lastChange != nil)
    }

    @Test func anotherMemoryStartsAFreshGraph() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let other = try Brain.initialize(at: home.url.appending(path: "Brain-work"), language: .en)
        try write(other.root, "memory/client-site/MEMORY.md", "Client notes.\n")
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.selected = "memory/website/decision_pricing.md"
        await model.refresh(root: other.root)
        #expect(model.graph.node("memory/website/decision_pricing.md") == nil)
        #expect(model.graph.node("project:client-site")?.file == "memory/client-site/MEMORY.md")
        #expect(model.selected == nil && model.pulses.isEmpty)
    }

    @Test func aNoteReadsWithoutItsFrontmatter() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        let preview = await model.loadPreview("memory/website/decision_pricing.md")
        #expect(preview.hasPrefix("# Pricing"))
        #expect(!preview.contains("identity: studio"))
        #expect(model.fileURL("memory/website/decision_pricing.md")?.lastPathComponent == "decision_pricing.md")
        // A project's bubble is its index: it opens and reads as MEMORY.md; without an index, it opens its folder.
        #expect(model.fileURL("project:website")?.lastPathComponent == "MEMORY.md")
        #expect(await model.loadPreview("project:website").hasPrefix("- [Pricing]"))
        #expect(model.fileURL("project:mobile-app")?.lastPathComponent == "mobile-app")
        #expect(await model.loadPreview("project:mobile-app").isEmpty)
        #expect(model.authors["project:website"]?.slug == "studio")
        #expect(await model.loadPreview("memory/../../outside.md").isEmpty)
    }

    @Test func switchingMemoryWhileReadingShowsTheNewOne() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let other = try Brain.initialize(at: home.url.appending(path: "Brain-work"), language: .en)
        try write(other.root, "memory/client-site/decision_scope.md", "Scope.\n")
        let model = MemoryGraphModel(animates: false)
        // The first memory starts reading; the person picks the other one before that read ends.
        let first = Task { await model.refresh(root: brain.root) }
        await Task.yield()
        await model.refresh(root: other.root)
        await first.value
        #expect(model.root?.lastPathComponent == "Brain-work")
        #expect(model.graph.node("memory/client-site/decision_scope.md") != nil)
        #expect(model.graph.node("memory/website/decision_pricing.md") == nil)
    }

    @Test func theHistoryIsReadAgainOnlyWhenTheMemoryMoves() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        await model.refresh(root: brain.root)
        await model.refresh(root: brain.root)
        #expect(model.historyReads == 1)
        try write(brain.root, "memory/website/feedback_tone.md", "Plain words.\n")
        try BrainGit(brain: brain).commitAll(authorName: "Personal", authorEmail: "personal@brainmerge.local", message: "Brain update by Personal")
        await model.refresh(root: brain.root)
        #expect(model.historyReads == 2)
        #expect(model.authors["memory/website/feedback_tone.md"]?.slug == "personal")
    }

    @Test func withReducedMotionTheLayoutSettlesOutOfSight() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        model.reduceMotion = true
        await model.refresh(root: brain.root)
        while let task = model.settleTask { await task.value }
        #expect(model.layout.count == 5)
        #expect(model.layout.isSettled)
        #expect(!model.isMoving)
    }

    @Test func aHoverOrAHighlightThatLostItsNotesIsForgotten() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        try write(brain.root, "memory/website/draft.md", "Draft.\n")
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.hovered = "memory/website/draft.md"
        model.highlightedAccount = "client"
        try FileManager.default.removeItem(at: brain.root.appending(path: "memory/website/draft.md"))
        await model.refresh(root: brain.root)
        #expect(model.hovered == nil)
        #expect(model.highlightedAccount == nil)
        model.pointer = CGPoint(x: 3, y: 4); model.hovered = "project:website"
        model.pointerLeft()
        #expect(model.pointer == nil && model.hovered == nil)
    }

    @Test func revealBringsAnOffscreenNoteToTheCenter() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.viewSize = CGSize(width: 800, height: 600)
        let id = "memory/mobile-app/project_launch.md"
        let p = try #require(model.position(of: id))
        model.camera.center = CGPoint(x: p.x + 5_000, y: p.y)
        model.reveal(id)
        #expect(model.camera.center == p)
        model.camera.center = CGPoint(x: p.x + 10, y: p.y)
        model.reveal(id)
        #expect(model.camera.center == CGPoint(x: p.x + 10, y: p.y))   // already in view: the camera stays
    }

    @Test func theCameraFitsTheGraphAndZoomsAroundThePointer() {
        var camera = GraphCamera()
        camera.fit(CGRect(x: -100, y: -50, width: 200, height: 100), in: CGSize(width: 800, height: 400))
        #expect(camera.center == CGPoint(x: 0, y: 0))
        #expect(camera.scale > 2 && camera.scale <= GraphCamera.maxScale)
        let size = CGSize(width: 800, height: 400)
        let pointer = CGPoint(x: 600, y: 100)
        let before = camera.toWorld(pointer, in: size)
        camera.zoom(by: 0.5, around: pointer, in: size)
        let after = camera.toWorld(pointer, in: size)
        #expect(abs(before.x - after.x) < 0.001 && abs(before.y - after.y) < 0.001)
        let round = camera.toScreen(camera.toWorld(CGPoint(x: 10, y: 20), in: size), in: size)
        #expect(abs(round.x - 10) < 0.0001 && abs(round.y - 20) < 0.0001)
    }
}
