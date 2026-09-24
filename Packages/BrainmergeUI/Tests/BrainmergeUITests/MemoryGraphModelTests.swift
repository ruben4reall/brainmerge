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
        #expect(model.neighbors(of: "memory/website/decision_pricing.md") == ["memory/website/MEMORY.md", "memory/mobile-app/project_launch.md", "project:website"])
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
        #expect(model.graph.node("memory/client-site/MEMORY.md") != nil)
        #expect(model.selected == nil && model.pulses.isEmpty)
    }

    @Test func aNoteReadsWithoutItsFrontmatter() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        let preview = model.preview("memory/website/decision_pricing.md")
        #expect(preview.hasPrefix("# Pricing"))
        #expect(!preview.contains("identity: studio"))
        #expect(model.fileURL("memory/website/decision_pricing.md")?.lastPathComponent == "decision_pricing.md")
        #expect(model.fileURL("project:website")?.lastPathComponent == "website")
        #expect(model.preview("project:website").isEmpty)
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
