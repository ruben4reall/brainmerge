import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// An Obsidian vault drawn the way Obsidian draws it: every file is its own node (no project hubs, MEMORY.md is a note),
/// links keep their direction, and the vault's own graph settings decide what shows and in which color.
@Suite struct ObsidianVaultGraphTests {
    func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The owner's layout of folders, with neutral project and people names.
    func ownersVault(_ home: TempHome) throws -> URL {
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "HOME.md", "[[Idea]] [[Orchard]] [[Studio]] [[Board.canvas]] [[2026-09-24]] [[MEMORY]] [[Daily]]\n")
        try write(root, "00 Inbox/Idea.md", "[[HOME]]\n")
        try write(root, "01 Journal/2026-09-24.md", "[[HOME]] [[Orchard]]\n")
        try write(root, "02 Projets/Orchard/Orchard.md", "[[Orchard · Tech]] [[Ada Lovelace]]\n")
        try write(root, "02 Projets/Orchard/Orchard · Tech.md", "[[Orchard]]\n")
        try write(root, "02 Projets/Studio/Studio.md", "[[Craft]]\n")
        try write(root, "03 Domaines/Craft.md", "[[Studio]]\n")
        try write(root, "06 Personnes/Ada Lovelace.md", "Pioneer.\n")
        try write(root, "06 Personnes/Grace Hopper.md", "[[Ada Lovelace]]\n")
        try write(root, "07 Archives/Old plan.md", "[[Orchard]]\n")
        try write(root, "98 Me\u{301}moire Claude/feedback_tone.md", "[[Orchard]]\n")
        try write(root, "98 Me\u{301}moire Claude/02 Projets/Orchard/decision.md", "[[Orchard]]\n")
        try write(root, "98 Me\u{301}moire Claude/MEMORY.md", "[[feedback_tone]] [[decision]]\n")
        try write(root, "98 Me\u{301}moire Claude/Sessions/2026-09-24 Launch.md", "[[feedback_tone]]\n")
        try write(root, "99 Système/Templates/Daily.md", "[[HOME]]\n")
        try write(root, "99 Système/Dashboard.base", "views: []\n")
        try write(root, "Board.canvas", #"{"nodes":[],"edges":[]}"#)
        try write(root, "Lonely.md", "No links.\n")
        try write(root, ".obsidian/graph.json", """
        {"search": "-path:\\"01 Journal\\" -path:\\"99 Système\\" -path:\\"98 Mémoire Claude/Sessions\\" -file:\\"MEMORY\\"",
         "showAttachments": false, "hideUnresolved": true, "showOrphans": true,
         "colorGroups": [
           {"query": "path:\\"98 Mémoire Claude\\"", "color": {"a": 1, "rgb": 1419967}},
           {"query": "path:\\"00 Inbox\\"", "color": {"a": 1, "rgb": 16612884}},
           {"query": "path:\\"07 Archives\\"", "color": {"a": 1, "rgb": 8818326}},
           {"query": "path:\\"02 Projets/Orchard\\" OR path:\\"03 Domaines/Orchard.md\\" OR path:\\"06 Personnes/Ada Lovelace.md\\"", "color": {"a": 1, "rgb": 11887901}},
           {"query": "path:\\"02 Projets/Studio\\" OR path:\\"03 Domaines/Craft.md\\"", "color": {"a": 1, "rgb": 15092096}},
           {"query": "path:\\"05 Ressources\\" OR path:\\"06 Personnes\\"", "color": {"a": 1, "rgb": 11133771}}
         ]}
        """)
        try write(root, ".obsidian/app.json", #"{"userIgnoreFilters": ["99 Système/Templates/"]}"#)
        return root
    }

    func shown(_ root: URL) -> ObsidianGraphFilter.Shown {
        let graph = MemoryGraphBuilder(root: root, style: .vault).build().graph
        return ObsidianGraphFilter.apply(ObsidianGraphSettings.read(vault: root), to: graph)
    }

    @Test func aVaultHasNoHubsAndItsIndexIsAnOrdinaryNote() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "memory/website/MEMORY.md", "- [[decision]]\n")
        try write(root, "memory/website/decision.md", "Keep the offer.\n")
        let vault = MemoryGraphBuilder(root: root, style: .vault).build()
        #expect(vault.graph.nodes.map(\.id).sorted() == ["memory/website/MEMORY.md", "memory/website/decision.md"])
        #expect(vault.graph.nodes.allSatisfy { $0.kind == .note && $0.project == nil })
        #expect(vault.graph.edges == [MemoryGraph.Edge("memory/website/MEMORY.md", "memory/website/decision.md")])
        #expect(vault.changed.sorted() == ["memory/website/MEMORY.md", "memory/website/decision.md"])
        // The same folder as a Brainmerge memory keeps its hub.
        #expect(MemoryGraphBuilder(root: root).build().graph.node("project:website") != nil)
    }

    /// A link both ways is one line between two notes but two links: each note weighs both, as in Obsidian.
    @Test func mutualLinksAreOneLineAndTwoLinks() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "A.md", "[[B]] [[B|again]]\n")
        try write(root, "B.md", "[[A]]\n")
        try write(root, "C.md", "[[A]] [[C]]\n")
        let graph = MemoryGraphBuilder(root: root, style: .vault).build().graph
        #expect(graph.edges == [MemoryGraph.Edge("A.md", "B.md"), MemoryGraph.Edge("A.md", "C.md")])
        #expect(Set(graph.links) == [MemoryGraph.Link(source: "A.md", target: "B.md"), MemoryGraph.Link(source: "B.md", target: "A.md"),
                                     MemoryGraph.Link(source: "C.md", target: "A.md")])
        #expect(graph.weights() == ["A.md": 3, "B.md": 2, "C.md": 1])
    }

    /// Canvases and bases are nodes like notes. Attachments and links to nothing are nodes too, of their own kind,
    /// which the vault's settings show or hide; a Brainmerge memory draws none of them.
    @Test func canvasesBasesAttachmentsAndUnresolvedLinks() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "Plan.md", "[[Board.canvas]] [[Tasks.base]] ![[pic.png]] [[Missing]] [s](assets/scan.pdf) [[Board]]\n")
        try write(root, "Board.canvas", #"{"nodes":[{"type":"file","file":"Plan.md"}]}"#)
        try write(root, "Tasks.base", "views: []\n")
        try write(root, "pic.png", "png")
        try write(root, "assets/scan.pdf", "pdf")
        try write(root, "assets/unlinked.jpg", "jpg")
        let graph = MemoryGraphBuilder(root: root, style: .vault).build().graph
        #expect(graph.node("Board.canvas")?.kind == .note && graph.node("Board.canvas")?.title == "Board.canvas")
        #expect(graph.node("Tasks.base")?.kind == .note)
        #expect(graph.node("pic.png")?.kind == .attachment && graph.node("assets/unlinked.jpg")?.kind == .attachment)
        let missing = try #require(graph.node("unresolved:missing"))
        #expect(missing.kind == .unresolved)
        #expect(missing.title == "Missing" && missing.file == nil)
        // [[Board]] means Board.md, which does not exist: a second unresolved node, never the canvas.
        #expect(graph.nodes.filter { $0.kind == .unresolved }.map(\.title).sorted() == ["Board", "Missing"])
        func linked(_ b: String) -> Bool { graph.edges.contains(MemoryGraph.Edge("Plan.md", b)) }
        #expect(linked("Board.canvas") && linked("Tasks.base") && linked("pic.png") && linked("assets/scan.pdf") && linked(missing.id))
        // Canvases are not read for links: a canvas that points at a note draws no line of its own.
        #expect(!graph.links.contains { $0.source == "Board.canvas" })
        let memory = MemoryGraphBuilder(root: root).build().graph
        #expect(memory.nodes.map(\.id) == ["Plan.md"] && memory.edges.isEmpty)
    }

    /// The owner's search, Excluded files and color groups, rebuilt in a temporary vault.
    @Test func theOwnersFilterAndGroupsApplyLikeObsidian() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try ownersVault(home)
        let result = shown(root)
        let ids = Set(result.graph.nodes.map(\.id))
        for hidden in ["01 Journal/2026-09-24.md", "98 Mémoire Claude/MEMORY.md", "98 Mémoire Claude/Sessions/2026-09-24 Launch.md",
                       "99 Système/Templates/Daily.md", "99 Système/Dashboard.base"] {
            #expect(!ids.contains(hidden), "\(hidden) is filtered out")
        }
        let expected: Set<String> = ["HOME.md", "00 Inbox/Idea.md", "02 Projets/Orchard/Orchard.md", "02 Projets/Orchard/Orchard · Tech.md",
                                     "02 Projets/Studio/Studio.md", "03 Domaines/Craft.md", "06 Personnes/Ada Lovelace.md", "06 Personnes/Grace Hopper.md",
                                     "07 Archives/Old plan.md", "98 Mémoire Claude/feedback_tone.md", "98 Mémoire Claude/02 Projets/Orchard/decision.md",
                                     "Board.canvas", "Lonely.md"]
        #expect(ids == expected)
        func color(_ id: String) -> String? { result.colors[id]?.hex }
        #expect(color("98 Mémoire Claude/feedback_tone.md") == "#15AABF")
        // First match wins: a memory note under a project's path stays teal, Ada stays in her project's group.
        #expect(color("98 Mémoire Claude/02 Projets/Orchard/decision.md") == "#15AABF")
        #expect(color("06 Personnes/Ada Lovelace.md") == "#B5651D")
        #expect(color("06 Personnes/Grace Hopper.md") == "#A9E34B")
        #expect(color("00 Inbox/Idea.md") == "#FD7E14")
        #expect(color("07 Archives/Old plan.md") == "#868E96")
        #expect(color("02 Projets/Studio/Studio.md") == "#E64980" && color("03 Domaines/Craft.md") == "#E64980")
        #expect(color("HOME.md") == nil && color("Board.canvas") == nil && color("Lonely.md") == nil)
    }

    @Test func aHiddenNoteTakesItsLinesAndLinksWithIt() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try ownersVault(home)
        let result = shown(root)
        let ids = Set(result.graph.nodes.map(\.id))
        #expect(result.graph.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
        #expect(result.graph.links.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
        #expect(!result.graph.edges.contains(MemoryGraph.Edge("HOME.md", "01 Journal/2026-09-24.md")))
        #expect(result.graph.edges.contains(MemoryGraph.Edge("HOME.md", "00 Inbox/Idea.md")))
        // HOME links to seven notes, three of them hidden: four lines, and its weight counts only what shows.
        #expect(result.graph.edges.filter { $0.from == "HOME.md" || $0.to == "HOME.md" }.count == 4)
        #expect(result.graph.weights()["HOME.md"] == 5)   // four out, one back from Idea
    }

    @Test func orphansUnresolvedAndAttachmentsFollowTheSettings() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "A.md", "[[B]] [[Ghost]] ![[pic.png]]\n")
        try write(root, "B.md", "Linked.\n")
        try write(root, "Lonely.md", "Alone.\n")
        try write(root, "Only to hidden.md", "[[Secret]]\n")
        try write(root, "Private/Secret.md", "Hidden.\n")
        try write(root, "pic.png", "png")
        let graph = MemoryGraphBuilder(root: root, style: .vault).build().graph
        var s = ObsidianGraphSettings()
        s.search = "-path:Private"
        var shown = Set(ObsidianGraphFilter.apply(s, to: graph).graph.nodes.map(\.id))
        // Obsidian's defaults: orphans shown, unresolved links shown, attachments hidden.
        #expect(shown.contains("Lonely.md") && shown.contains("Only to hidden.md"))
        #expect(shown.contains { $0.hasPrefix("unresolved:") } && !shown.contains("pic.png"))
        s.showOrphans = false; s.hideUnresolved = true; s.showAttachments = true
        shown = Set(ObsidianGraphFilter.apply(s, to: graph).graph.nodes.map(\.id))
        // Orphans are judged on what shows: a note whose only link goes to a hidden note is an orphan too.
        #expect(shown == ["A.md", "B.md", "pic.png"])
        // An unresolved link only shows while a shown note points at it.
        s.hideUnresolved = false; s.search = "-file:A.md"
        shown = Set(ObsidianGraphFilter.apply(s, to: graph).graph.nodes.map(\.id))
        #expect(!shown.contains { $0.hasPrefix("unresolved:") })
    }

    /// Excluded files (app.json) are path prefixes, or regular expressions between slashes, whatever the case.
    @Test func excludedFilesAreHidden() throws {
        var s = ObsidianGraphSettings()
        s.ignoreFilters = ["99 système/templates/", "/\\.draft\\.md$/", "/[unclosed/"]
        #expect(s.isIgnored("99 Système/Templates/Daily.md"))
        #expect(!s.isIgnored("Notes/99 Système/Templates/Daily.md"))
        #expect(s.isIgnored("Notes/Plan.DRAFT.md"))
        #expect(!s.isIgnored("Notes/Plan.md"))
    }

    /// Excluded files hide what the search keeps, by folder or by pattern, and take their lines, links and colors with them.
    @Test func excludedFilesHideWhatTheSearchKeeps() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try ownersVault(home)
        try write(root, ".obsidian/app.json", #"{"userIgnoreFilters": ["07 Archives/", "/tech\\.md$/"]}"#)
        let result = shown(root)
        let ids = Set(result.graph.nodes.map(\.id))
        let excluded = ["07 Archives/Old plan.md", "02 Projets/Orchard/Orchard · Tech.md"]
        for path in excluded { #expect(!ids.contains(path), "\(path) is excluded") }
        #expect(ids.contains("02 Projets/Orchard/Orchard.md") && ids.contains("HOME.md"))
        #expect(!result.graph.edges.contains { excluded.contains($0.from) || excluded.contains($0.to) })
        #expect(!result.graph.links.contains { excluded.contains($0.source) || excluded.contains($0.target) })
        #expect(excluded.allSatisfy { result.colors[$0] == nil })
    }

    /// The cap on notes counts only what the vault shows: newer files hidden by the search, the Excluded files or the
    /// attachments setting never push a shown note out, nor make the graph say it was cut short. A link to a hidden note
    /// still finds its file: it is not drawn, and it is no unresolved link either.
    @Test func theCapCountsOnlyWhatTheVaultShows() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        func add(_ path: String, _ text: String, at seconds: TimeInterval) throws {
            try write(root, path, text)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)],
                                                  ofItemAtPath: root.appending(path: path).path)
        }
        try add("Notes/A.md", "[[B]] [[2026-09-24]] [[Draft]]\n", at: 1_000)
        try add("Notes/B.md", "[[C]]\n", at: 1_001)
        try add("Notes/C.md", "[[A]]\n", at: 1_002)
        for i in 0..<4 { try add("Journal/2026-09-2\(i + 1).md", "[[A]]\n", at: 2_000 + Double(i)) }
        try add("Drafts/Draft.md", "[[A]]\n", at: 3_000)
        for i in 0..<4 { try add("assets/p\(i).png", "png", at: 4_000 + Double(i)) }
        var settings = ObsidianGraphSettings()
        settings.search = "-path:Journal"
        settings.ignoreFilters = ["Drafts/"]
        let builder = MemoryGraphBuilder(root: root, style: .vault, maxNotes: 3)
        let result = builder.build(showing: ObsidianGraphFilter.showsFile(settings))
        #expect(!result.truncated && !result.attachmentsTruncated)
        let shown = ObsidianGraphFilter.apply(settings, to: result.graph)
        #expect(Set(shown.graph.nodes.map(\.id)) == ["Notes/A.md", "Notes/B.md", "Notes/C.md"])
        #expect(shown.graph.edges.count == 3)
        // One more note the vault shows: now the graph is cut short, and keeps the three most recent.
        try add("Notes/D.md", "[[A]]\n", at: 1_003)
        let more = builder.build(showing: ObsidianGraphFilter.showsFile(settings))
        #expect(more.truncated)
        #expect(Set(ObsidianGraphFilter.apply(settings, to: more.graph).graph.nodes.map(\.id)) == ["Notes/B.md", "Notes/C.md", "Notes/D.md"])
    }

    /// A vault that cannot be opened (macOS asked and was refused, or its permissions say no) is said so, never drawn
    /// as an empty vault; a locked folder inside it is only left out.
    @Test func aVaultThatCannotBeReadIsSaidSo() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        let locked = root.appending(path: "Private", directoryHint: .isDirectory)
        try write(root, "A.md", "[[B]]\n")
        try write(root, "Private/B.md", "Hidden.\n")
        let fm = FileManager.default
        defer { for url in [root, locked] { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) } }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        let partly = MemoryGraphBuilder(root: root, style: .vault).build()
        #expect(!partly.refused && partly.graph.node("A.md") != nil && partly.graph.node("Private/B.md") == nil)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        let refused = MemoryGraphBuilder(root: root, style: .vault).build()
        #expect(refused.refused && refused.graph.nodes.isEmpty)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        #expect(!MemoryGraphBuilder(root: root, style: .vault).build().refused)
    }

    /// The vault is only ever read: building, reading its settings and filtering leave every file and date as it was.
    @Test func theVaultIsNeverWritten() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = try ownersVault(home)
        func snapshot() throws -> [String: Date] {
            var files: [String: Date] = [:]
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let walker = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
            for case let url as URL in walker {
                files[url.path] = try url.resourceValues(forKeys: Set(keys)).contentModificationDate
            }
            return files
        }
        let before = try snapshot()
        Thread.sleep(forTimeInterval: 1.1)
        let builder = MemoryGraphBuilder(root: root, style: .vault)
        for _ in 0..<2 { _ = ObsidianGraphFilter.apply(ObsidianGraphSettings.read(vault: root), to: builder.build().graph) }
        _ = ObsidianVaults.isVault(root)
        #expect(try snapshot() == before)
    }
}
