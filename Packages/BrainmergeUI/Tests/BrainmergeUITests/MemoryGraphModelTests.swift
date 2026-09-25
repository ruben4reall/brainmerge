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

    // MARK: An Obsidian vault

    /// A vault that is also a git repository saved by an account: the vault look must not depend on that.
    func vault(_ home: TempHome, graph: String) throws -> URL {
        let brain = try Brain.initialize(at: home.url.appending(path: "Notes Vault"), language: .en)
        let root = brain.root
        try write(root, "memory/website/MEMORY.md", "[[decision]]\n")
        try write(root, "memory/website/decision.md", "[[plan]]\n")
        try write(root, "Projects/plan.md", "[[decision]]\n")
        try write(root, "Journal/today.md", "[[plan]]\n")
        try write(root, ".obsidian/graph.json", graph)
        try BrainGit(brain: brain).commitAll(authorName: "Studio", authorEmail: "studio@brainmerge.local", message: "Brain update by Studio")
        return root
    }

    static let graphJSON = #"{"search": "-path:Journal", "scale": 0.55, "colorGroups": [{"query": "path:Projects", "color": {"a": 1, "rgb": 1419967}}]}"#

    @Test func aVaultIsDrawnTheWayObsidianDrawsIt() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        model.backingScale = 2
        await model.refresh(root: root, style: .vault)
        #expect(model.style == .vault)
        // No hubs, the index is a note, the search hides the journal, nobody's color: the vault's own groups instead.
        #expect(!model.graph.nodes.contains { $0.kind == .project })
        #expect(model.graph.node("memory/website/MEMORY.md") != nil)
        #expect(model.graph.node("Journal/today.md") == nil)
        #expect(model.authors.isEmpty && model.historyReads == 0)
        #expect(model.groupColors["Projects/plan.md"]?.hex == "#15AABF" && model.groupColors["BRAIN.md"] == nil)
        // Obsidian's forces, weights and saved zoom, in Obsidian's units (device pixels, two per point here).
        #expect(model.layout.forces == .obsidian(model.settings))
        #expect(model.weights["memory/website/decision.md"] == 3)
        #expect(model.camera.scale == 0.55 && model.camera.center == .zero && model.camera.unit == 0.5)
        #expect(model.fitted)
        // A link both ways is one line, and two springs.
        #expect(model.lineIndices.count == model.graph.edges.count)
        #expect(model.layout.linkIndices.count == model.graph.links.count)
        #expect(model.graph.links.count == model.graph.edges.count + 1)
    }

    @Test func aVaultNeverPulsesAndSaysWhatChanged() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        try write(root, "Projects/new.md", "[[plan]]\n")
        await model.refresh(root: root, style: .vault)
        #expect(model.graph.node("Projects/new.md") != nil)
        #expect(model.pulses.isEmpty && model.lastChange != nil)
    }

    /// Obsidian writes graph.json as its settings change: the graph follows, but a new zoom alone never moves the view.
    @Test func graphJSONIsReadAgainWhenItChanges() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        model.camera.scale = 1.7
        try write(root, ".obsidian/graph.json", #"{"search": "-path:Journal", "scale": 3}"#)
        await model.refresh(root: root, style: .vault)
        #expect(model.camera.scale == 1.7)
        #expect(model.groupColors.isEmpty)
        try write(root, ".obsidian/graph.json", #"{"search": "", "linkDistance": 100}"#)
        await model.refresh(root: root, style: .vault)
        #expect(model.graph.node("Journal/today.md") != nil)
        #expect(model.layout.forces.linkDistance == 100 && !model.layout.isSettled)
    }

    /// Hovering a note fades the unrelated ones and their lines to a fifth, softly as Obsidian does, at once with Reduce Motion.
    @Test func hoverFadesWhatIsUnrelated() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        model.hovered = "Projects/plan.md"
        #expect(model.isMoving)
        model.tick()
        #expect(model.fade("BRAIN.md") < 1 && model.fade("BRAIN.md") > 0.2)
        for _ in 0..<120 { model.tick() }
        #expect(model.fade("BRAIN.md") == 0.2 && model.fade("Projects/plan.md") == 1 && model.fade("memory/website/decision.md") == 1)
        #expect(model.lineFade == 0.2)
        model.reduceMotion = true
        model.hovered = nil
        model.tick()
        #expect(model.fade("BRAIN.md") == 1 && model.lineFade == 1)
    }

    @Test func aVaultAndAMemoryDoNotShareTheirLook() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let memory = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        await model.refresh(root: memory.root)
        #expect(model.style == .memory && model.layout.forces == .brainmerge && model.camera.unit == 1)
        #expect(model.graph.node("project:website") != nil && model.groupColors.isEmpty)
        // The same folder, once as a memory and once as a vault, is two different graphs.
        await model.refresh(root: memory.root, style: .vault)
        #expect(model.graph.node("project:website") == nil && model.graph.node("memory/website/MEMORY.md") != nil)
        // In a vault, a link to nothing has no file to open.
        #expect(model.fileURL("unresolved:missing") == nil)
    }

    /// Obsidian's saved zoom is used as saved, anywhere in Obsidian's own range, far beyond a memory's.
    @Test func aVaultOpensAtItsSavedZoomInObsidiansRange() async throws {
        for scale in [0.01, 6.0] {
            let home = try TempHome(); defer { home.remove() }
            let root = try vault(home, graph: #"{"scale": \#(scale)}"#)
            let model = MemoryGraphModel(animates: false)
            await model.refresh(root: root, style: .vault)
            #expect(model.camera.scale == CGFloat(scale))
            #expect(model.camera.zoomRange == GraphCamera.obsidianZoom)
        }
    }

    /// A vault is drawn in the screen's pixels: moving the window to a screen of another density follows it.
    @Test func aVaultFollowsTheScreensDensity() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        model.backingScale = 2
        await model.refresh(root: root, style: .vault)
        #expect(model.camera.unit == 0.5)
        model.backingScale = 1
        #expect(model.camera.unit == 1)
        await model.refresh(root: home.url.appending(path: "Notes Vault"))
        model.backingScale = 2
        #expect(model.camera.unit == 1)   // a memory is drawn in points
    }

    /// A link both ways is one line but two arrows, one at each end.
    @Test func aMutualLinkHasOneLineAndTwoArrows() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: #"{"showArrow": true}"#)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        #expect(model.settings.showArrow)
        let decision = try #require(model.layout.indexOf("memory/website/decision.md"))
        let plan = try #require(model.layout.indexOf("Projects/plan.md"))
        func pair(_ p: (Int, Int)) -> Set<Int> { [p.0, p.1] }
        #expect(model.lineIndices.filter { pair($0) == [decision, plan] }.count == 1)
        #expect(model.arrowIndices.contains { $0 == (decision, plan) } && model.arrowIndices.contains { $0 == (plan, decision) })
        #expect(model.arrowIndices.count == model.graph.links.count)
    }

    /// A change to a note the vault's filters hide is no change to the graph.
    @Test func aChangeToAHiddenNoteChangesNothing() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        try write(root, "Journal/today.md", "[[plan]] and more\n")
        try write(root, "Journal/tomorrow.md", "[[plan]]\n")
        await model.refresh(root: root, style: .vault)
        #expect(model.lastChange == nil)
        #expect(model.graph.node("Journal/tomorrow.md") == nil)
    }

    /// Editing only the Excluded files (app.json) is picked up like a change to graph.json.
    @Test func excludedFilesAreReadAgainWhenTheyChange() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        #expect(model.graph.node("Projects/plan.md") != nil)
        try write(root, ".obsidian/app.json", #"{"userIgnoreFilters": ["Projects/"]}"#)
        await model.refresh(root: root, style: .vault)
        #expect(model.graph.node("Projects/plan.md") == nil)
        #expect(!model.graph.edges.contains { $0.from == "Projects/plan.md" || $0.to == "Projects/plan.md" })
        await model.refresh(root: root, style: .vault)
        #expect(model.graph.node("Projects/plan.md") == nil)
    }

    /// A vault macOS refuses to open says so; once allowed, it shows.
    @Test func aVaultThatMayNotBeReadSaysSo() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: Self.graphJSON)
        let fm = FileManager.default
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: root, style: .vault)
        #expect(model.refused && model.graph.nodes.isEmpty)
        #expect(MemoryGraphView.emptyText(vault: true, refused: true).hasPrefix("Brainmerge may not read this vault."))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        await model.refresh(root: root, style: .vault)
        #expect(!model.refused && model.graph.node("Projects/plan.md") != nil)
    }

    /// A vault that hides its attachments is not said to be cut short because of them.
    @Test func attachmentsOnlyCountAsCutWhenShown() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: #"{"showAttachments": false}"#)
        for i in 0..<12 { try write(root, "assets/a\(i).png", "png") }
        let model = MemoryGraphModel(animates: false, maxNotes: 10)
        await model.refresh(root: root, style: .vault)
        #expect(!model.truncated)
        try write(root, ".obsidian/graph.json", #"{"showAttachments": true}"#)
        await model.refresh(root: root, style: .vault)
        #expect(model.truncated)
    }

    /// In a vault a node is grabbed anywhere on it, however large the zoom draws it, and within a finger's width when
    /// small. A memory keeps the finger's width.
    @Test func aLargeNodeIsGrabbedAnywhereOnIt() async throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try vault(home, graph: #"{"nodeSizeMultiplier": 3}"#)
        let model = MemoryGraphModel(animates: false)
        model.backingScale = 2
        await model.refresh(root: root, style: .vault)
        let target = "memory/website/decision.md"
        for (i, node) in model.graph.nodes.enumerated() where node.id != target { model.drag(node.id, to: CGPoint(x: 10_000 * (i + 1), y: 0)) }
        model.drag(target, to: .zero)
        model.endDrag()
        let size = CGSize(width: 800, height: 600)
        model.camera.center = .zero
        model.camera.scale = 8
        // Weight 3, size 8 times 3, drawn at 24 x sqrt(8) x 0.5: about 34 points.
        #expect(model.node(at: CGPoint(x: 430, y: 300), in: size) == target)
        #expect(model.node(at: CGPoint(x: 435, y: 300), in: size) == target)
        #expect(model.node(at: CGPoint(x: 437, y: 300), in: size) == nil)
        model.camera.scale = 0.01
        #expect(model.node(at: CGPoint(x: 412, y: 300), in: size) == target)
        #expect(model.node(at: CGPoint(x: 416, y: 300), in: size) == nil)
        let memory = try brain(home)
        await model.refresh(root: memory.root)
        let note = "memory/website/decision_pricing.md"
        for (i, node) in model.graph.nodes.enumerated() where node.id != note { model.drag(node.id, to: CGPoint(x: 10_000 * (i + 1), y: 0)) }
        model.drag(note, to: .zero)
        model.endDrag()
        model.camera.center = .zero
        model.camera.scale = 4
        #expect(model.node(at: CGPoint(x: 412, y: 300), in: size) == note)
        #expect(model.node(at: CGPoint(x: 430, y: 300), in: size) == nil)
    }

    /// The keyboard and VoiceOver go through hubs first, then every other node by name, whatever its kind.
    @Test func nodesAreOrderedHubsFirstThenByName() {
        func node(_ id: String, _ title: String, _ kind: MemoryGraph.Node.Kind) -> MemoryGraph.Node {
            MemoryGraph.Node(id: id, title: title, kind: kind, project: nil, modified: nil)
        }
        let nodes = [node("notes/d.md", "d", .note), node("c.png", "c.png", .attachment), node("unresolved:b", "b", .unresolved),
                     node("a.md", "a", .note), node("project:z", "z", .project), node("e.pdf", "e.pdf", .attachment), node("f.md", "f", .note)]
        #expect(MemoryGraphView.ordered(nodes).map(\.id) == ["project:z", "a.md", "unresolved:b", "c.png", "notes/d.md", "e.pdf", "f.md"])
    }

    /// Obsidian works in the screen's pixels: on a Retina screen one unit is half a point, so a saved zoom means the same.
    @Test func theCameraConvertsUnitsToPoints() {
        var camera = GraphCamera()
        camera.unit = 0.5
        let size = CGSize(width: 800, height: 600)
        #expect(camera.toScreen(CGPoint(x: 100, y: 0), in: size) == CGPoint(x: 450, y: 300))
        let back = camera.toWorld(CGPoint(x: 450, y: 300), in: size)
        #expect(abs(back.x - 100) < 1e-9 && abs(back.y) < 1e-9)
        camera.zoomRange = GraphCamera.obsidianZoom
        camera.zoom(by: 1000, around: CGPoint(x: 400, y: 300), in: size)
        #expect(camera.scale == 8)
        camera.zoom(by: 0.00001, around: CGPoint(x: 400, y: 300), in: size)
        #expect(camera.scale == 1.0 / 128)
        camera.fit(CGRect(x: -100, y: -50, width: 200, height: 100), in: size)
        let corner = camera.toScreen(CGPoint(x: 100, y: 0), in: size)
        #expect(abs(corner.x - (400 + 400 * 0.82)) < 0.001)
        // Dragging the background moves the world with the pointer, point for point, whatever the unit.
        camera.scale = 1
        let dragged = camera.dragged(from: CGPoint(x: 10, y: 20), by: CGSize(width: 100, height: -50))
        #expect(dragged == CGPoint(x: -190, y: 120))
    }
}
