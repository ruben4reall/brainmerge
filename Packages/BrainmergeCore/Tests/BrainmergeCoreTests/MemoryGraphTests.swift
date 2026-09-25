import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// The memory as a graph: notes are nodes, links between notes are edges, each project folder of the memory is a hub.
@Suite struct MemoryGraphTests {
    func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func folder() throws -> (TempHome, URL) {
        let home = try TempHome()
        let root = home.url.appending(path: "Brain", directoryHint: .isDirectory)
        try write(root, "BRAIN.md", "# Shared brain\n")
        try write(root, "memory/website/MEMORY.md", "- [Pricing](decision_pricing.md)\n- [Tone](feedback%20tone.md)\n- [Docs](https://example.com/a.md)\n")
        try write(root, "memory/website/decision_pricing.md", "---\nliens: [\"[[Client Brief]]\"]\n---\nKeep the offer. See [[feedback tone|the tone note]] and [[decision_pricing]].\n")
        try write(root, "memory/website/feedback tone.md", "Plain words. [[Nowhere]]\n")
        try write(root, "memory/mobile-app/MEMORY.md", "- [[project_launch#Dates]]\n")
        try write(root, "memory/mobile-app/project_launch.md", "Ship in October.\n")
        try write(root, "Clients/Client Brief.md", "The brief. [[DECISION_PRICING]]\n")
        try write(root, ".git/HEAD.md", "not a note\n")
        try write(root, ".obsidian/workspace.md", "not a note\n")
        try write(root, "memory/website/image.png", "png")
        return (home, root)
    }

    @Test func notesAndProjectHubsBecomeNodes() throws {
        let (home, root) = try folder(); defer { home.remove() }
        let graph = MemoryGraphBuilder(root: root).build().graph
        let notes = graph.nodes.filter { $0.kind == .note }.map(\.id).sorted()
        // A project's index (its MEMORY.md) is the project's own bubble, not a second bubble next to it.
        #expect(notes == ["BRAIN.md", "Clients/Client Brief.md", "memory/mobile-app/project_launch.md",
                          "memory/website/decision_pricing.md", "memory/website/feedback tone.md"])
        #expect(graph.nodes.filter { $0.kind == .project }.map(\.id).sorted() == ["project:mobile-app", "project:website"])
        let pricing = try #require(graph.node("memory/website/decision_pricing.md"))
        #expect(pricing.title == "decision_pricing" && pricing.project == "website" && pricing.file == "memory/website/decision_pricing.md")
        let hub = try #require(graph.node("project:website"))
        #expect(hub.title == "website" && hub.file == "memory/website/MEMORY.md" && hub.modified != nil)
        #expect(graph.node("Clients/Client Brief.md")?.project == nil)
    }

    @Test func aProjectWithoutAnIndexStillHasItsBubble() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Brain", directoryHint: .isDirectory)
        try write(root, "memory/api/decision_auth.md", "Tokens expire.\n")
        let graph = MemoryGraphBuilder(root: root).build().graph
        #expect(graph.node("project:api")?.file == nil)
        #expect(graph.edges.contains(MemoryGraph.Edge("project:api", "memory/api/decision_auth.md")))
    }

    @Test func wikilinksMarkdownLinksAndHubsBecomeEdges() throws {
        let (home, root) = try folder(); defer { home.remove() }
        let graph = MemoryGraphBuilder(root: root).build().graph
        func linked(_ a: String, _ b: String) -> Bool { graph.edges.contains(MemoryGraph.Edge(a, b)) }
        // Markdown links, relative and percent-encoded; web links ignored. The index speaks for its project.
        #expect(linked("project:website", "memory/website/decision_pricing.md"))
        #expect(linked("project:website", "memory/website/feedback tone.md"))
        // Wikilinks with an alias, with a heading, in the frontmatter, and matched by name whatever the case or folder.
        #expect(linked("memory/website/decision_pricing.md", "memory/website/feedback tone.md"))
        #expect(linked("project:mobile-app", "memory/mobile-app/project_launch.md"))
        #expect(graph.node("memory/website/MEMORY.md") == nil)
        #expect(!graph.edges.contains { $0.from.hasSuffix("MEMORY.md") || $0.to.hasSuffix("MEMORY.md") })
        #expect(linked("memory/website/decision_pricing.md", "Clients/Client Brief.md"))
        #expect(linked("Clients/Client Brief.md", "memory/website/decision_pricing.md"))
        // Every note of a project hangs from its hub.
        #expect(linked("project:website", "memory/website/feedback tone.md"))
        #expect(linked("project:mobile-app", "memory/mobile-app/project_launch.md"))
        // No self loop, no link to a note that does not exist, no duplicate.
        #expect(!graph.edges.contains { $0.from == $0.to })
        #expect(!graph.edges.contains { $0.to.contains("Nowhere") || $0.from.contains("Nowhere") })
        #expect(Set(graph.edges).count == graph.edges.count)
        #expect(graph.degree("memory/website/decision_pricing.md") == 3)   // its project (index included), the tone note, the brief
    }

    @Test func aSecondBuildOnlyReadsWhatChanged() throws {
        let (home, root) = try folder(); defer { home.remove() }
        let builder = MemoryGraphBuilder(root: root)
        let first = builder.build()
        #expect(first.readFiles == 7)
        #expect(Set(first.changed) == Set(first.graph.nodes.filter { $0.file != nil }.map(\.id)))   // notes, and projects with an index
        let second = builder.build()
        #expect(second.readFiles == 0 && second.changed.isEmpty && second.graph == first.graph)
        // A note is written, another appears: only they are read, only they are reported as changed.
        Thread.sleep(forTimeInterval: 1.1)
        try write(root, "memory/website/feedback tone.md", "Plain words. [[project_launch]]\n")
        try write(root, "memory/website/new_fact.md", "A new fact.\n")
        let third = builder.build()
        #expect(third.readFiles == 2)
        #expect(Set(third.changed) == ["memory/website/feedback tone.md", "memory/website/new_fact.md"])
        #expect(third.graph.edges.contains(MemoryGraph.Edge("memory/website/feedback tone.md", "memory/mobile-app/project_launch.md")))
        // A note removed disappears with its edges.
        try FileManager.default.removeItem(at: root.appending(path: "memory/website/new_fact.md"))
        let fourth = builder.build()
        #expect(fourth.graph.node("memory/website/new_fact.md") == nil)
        #expect(fourth.removed == ["memory/website/new_fact.md"])
    }

    @Test func aVeryLargeFolderIsCappedAndSaysSo() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        for i in 0..<30 { try write(root, "notes/n\(i).md", "[[n\((i + 1) % 30)]]\n") }
        let result = MemoryGraphBuilder(root: root, maxNotes: 20).build()
        #expect(result.graph.nodes.filter { $0.kind == .note }.count == 20)
        #expect(result.truncated)
    }

    @Test func linkTargetsAreParsed() {
        let text = "See [[A note]], [[folder/B|alias]], [[C#Heading]], ![[image.png]], [x](d%20e.md#top), [web](https://x.y/z.md), [mail](mailto:a@b.c) and `[[code]]`."
        #expect(MemoryGraph.linkTargets(in: text) == [.wiki("A note"), .wiki("folder/B"), .wiki("C"), .markdown("d e.md")])
    }

    @Test func linkTargetsSkipCodeAndReadEveryMarkdownForm() {
        let text = """
        | [[Table link\\|shown]] | [[Node.js]] | [[Brainmerge 0.3.0]] | ![[scan.PDF]] | [[board.canvas]]
        Inline `[[ -f x ]]` and ``a ` [[b]]`` are code.
        ```bash
        if [[ -f notes.md ]]; then echo "[x](inside.md)"; fi
        ```
        ~~~
        [[fenced]]
        ~~~
        [spaced](<My Note.md>) and [titled](plain.md "A title") and [x](../up/one.md)
        """
        #expect(MemoryGraph.linkTargets(in: text) == [.wiki("Table link"), .wiki("Node.js"), .wiki("Brainmerge 0.3.0"),
                                                      .markdown("My Note.md"), .markdown("plain.md"), .markdown("../up/one.md")])
    }

    @Test func aLineFullOfUnclosedBracketsIsParsedQuickly() {
        let text = String(repeating: "[[a ", count: 64_000)
        let start = Date()
        #expect(MemoryGraph.linkTargets(in: text).isEmpty)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func linksResolveLikeObsidian() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try write(root, "Tech/Node.js.md", "Runtime.\n")
        try write(root, "Releases/Brainmerge 0.3.0.md", "Shipped.\n")
        try write(root, "Other Note.md", "Elsewhere.\n")
        try write(root, "memory/mobile-app/project_launch.md", "Ship.\n")
        try write(root, "memory/website/decision.md", "[[Node.js]] [[Brainmerge 0.3.0]] [up](../mobile-app/project_launch.md)\n")
        try write(root, "Clients/Brief.md", "[abs](memory/website/decision.md) [short](Other%20Note.md) [gone](../../outside.md)\n")
        let graph = MemoryGraphBuilder(root: root).build().graph
        func linked(_ a: String, _ b: String) -> Bool { graph.edges.contains(MemoryGraph.Edge(a, b)) }
        #expect(linked("memory/website/decision.md", "Tech/Node.js.md"))
        #expect(linked("memory/website/decision.md", "Releases/Brainmerge 0.3.0.md"))
        #expect(linked("memory/website/decision.md", "memory/mobile-app/project_launch.md"))
        #expect(linked("Clients/Brief.md", "memory/website/decision.md"))
        #expect(linked("Clients/Brief.md", "Other Note.md"))
        #expect(graph.node("Tech/Node.js.md")?.title == "Node.js")
    }

    @Test func aMemoryReachedThroughASymlinkIsRead() throws {
        let home = try TempHome(); defer { home.remove() }
        let real = home.url.appending(path: "Dropbox/Brain", directoryHint: .isDirectory)
        try write(real, "memory/website/decision.md", "A decision.\n")
        let link = home.url.appending(path: "Brain")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let graph = MemoryGraphBuilder(root: link).build().graph
        #expect(graph.node("memory/website/decision.md") != nil)
    }

    @Test func noteSymlinksAreNeverFollowed() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "Brain", directoryHint: .isDirectory)
        try write(root, "memory/website/decision.md", "A decision.\n")
        try write(home.url, "secret/credentials.md", "not a note of this memory\n")
        try FileManager.default.createSymbolicLink(at: root.appending(path: "memory/website/leak.md"),
                                                   withDestinationURL: home.url.appending(path: "secret/credentials.md"))
        let result = MemoryGraphBuilder(root: root).build()
        #expect(result.graph.node("memory/website/leak.md") == nil)
        #expect(result.readFiles == 1)
    }

    @Test func changesAreReportedByBubble() throws {
        let (home, root) = try folder(); defer { home.remove() }
        let builder = MemoryGraphBuilder(root: root)
        _ = builder.build()
        Thread.sleep(forTimeInterval: 1.1)
        try write(root, "memory/website/MEMORY.md", "- [Pricing](decision_pricing.md)\n")
        #expect(builder.build().changed == ["project:website"])
        #expect(MemoryGraph.nodeID(forFile: "memory/website/MEMORY.md") == "project:website")
        #expect(MemoryGraph.nodeID(forFile: "memory/website/decision_pricing.md") == "memory/website/decision_pricing.md")
        #expect(MemoryGraph.nodeID(forFile: "memory/MEMORY.md") == "memory/MEMORY.md")
    }

    @Test func lastAuthorsComeFromTheHistory() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write(brain.root, "memory/website/a.md", "a\n")
        try git.commitAll(authorName: "Studio", authorEmail: "studio@brainmerge.local", message: "one")
        try write(brain.root, "memory/website/b.md", "b\n")
        try write(brain.root, "memory/website/a.md", "a again\n")
        try git.commitAll(authorName: "Personal", authorEmail: "personal@brainmerge.local", message: "two")
        let authors = try git.lastAuthors()
        #expect(authors["memory/website/a.md"]?.email == "personal@brainmerge.local")
        #expect(authors["memory/website/b.md"]?.name == "Personal")
        #expect(authors["BRAIN.md"]?.email == "studio@brainmerge.local")   // committed with the first save
    }

    @Test func accentedNamesKeepTheirAuthor() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write(brain.root, "memory/site/décision.md", "é\n")
        try write(brain.root, "02 Projects/Demo · DA.md", "DA\n")
        try git.commitAll(authorName: "Studio", authorEmail: "studio@brainmerge.local", message: "accents")
        let authors = try git.lastAuthors()
        #expect(authors["memory/site/décision.md"]?.name == "Studio")
        #expect(authors["02 Projects/Demo · DA.md"]?.name == "Studio")
    }

    @Test func theHeadCommitChangesOnlyWithASave() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        let first = git.head()
        #expect(git.head() == first)
        try write(brain.root, "memory/site/a.md", "a\n")
        try git.commitAll(authorName: "Studio", authorEmail: "studio@brainmerge.local", message: "one")
        #expect(git.head() != nil && git.head() != first)
    }
}
