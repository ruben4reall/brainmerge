import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// The Tidy tab's analysis: which notes Claude Code will not load, and what else needs a look, read from a memory laid out
/// like a real one (notes left in quick sessions' folders, a project with notes and no index, an index past its budget, a
/// copy left when linking, an index line to nothing, a change nobody saved). Reading never changes anything.
@Suite struct MemoryHealthTests {
    func write(_ text: String, _ path: String, in brain: Brain, daysAgo: Double? = nil) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let daysAgo { try age(path, in: brain, days: daysAgo) }
    }

    func age(_ path: String, in brain: Brain, days: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)],
                                              ofItemAtPath: brain.root.appending(path: path).path)
    }

    func folder(_ name: String, in brain: Brain) throws {
        try FileManager.default.createDirectory(at: brain.memoryDir(forProject: name), withIntermediateDirectories: true)
    }

    /// acme's index: 243 lines, deploy.md named on line 2, a note that is gone on line 3, prices.md only on line 230.
    static func acmeIndex() -> String {
        var lines = ["# acme", "- [Deploy](deploy.md) how we ship", "- [Gone](gone.md) a note that moved"]
        while lines.count < 229 { lines.append("- detail \(lines.count + 1)") }
        lines.append("- [Prices](prices.md) what we charge")
        while lines.count < 243 { lines.append("- detail \(lines.count + 1)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Like the owner's memory: most notes in quick sessions' folders, empty ones among them, a regular project folder that
    /// is empty, a project with notes and no index, and one whose index is long, misses a note and names one that is gone.
    func ownersLayout(_ home: TempHome) throws -> (Brain, BrainGit) {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write(Self.acmeIndex(), "memory/acme/MEMORY.md", in: brain)
        for note in ["deploy", "prices", "orphan", "deploy.work", "_archive/old"] { try write("# \(note)\n", "memory/acme/\(note).md", in: brain) }
        try write("# look\n", "memory/lumalab/look.md", in: brain)
        try write("# palette\n", "memory/lumalab/palette.md", in: brain)
        try folder("brainmerge", in: brain)
        try write("- [[route]]\n", "memory/beehive/MEMORY.md", in: brain)
        try write("# route\n", "memory/beehive/route.md", in: brain)
        try write("- [Pricing](beehive-pricing.md)\n- [Gear](beehive-gear.md)\n", "memory/scratch-2026-09-23-5050ce/MEMORY.md", in: brain)
        try write("# pricing\n", "memory/scratch-2026-09-23-5050ce/beehive-pricing.md", in: brain)
        try write("# gear\n", "memory/scratch-2026-09-23-5050ce/beehive-gear.md", in: brain)
        try folder("scratch-2026-09-10-5855fd", in: brain)
        try write("# Memory\n", "memory/scratch-2026-09-11-343e32/MEMORY.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        // Changed and never saved: route.md two days ago, look.md too but held back by the secret guard, palette.md just now.
        try write("# route, longer\n", "memory/beehive/route.md", in: brain, daysAgo: 2)
        try write("# look, longer\n", "memory/lumalab/look.md", in: brain, daysAgo: 2)
        try write("# palette, longer\n", "memory/lumalab/palette.md", in: brain)
        return (brain, git)
    }

    func report(_ brain: Brain, _ git: BrainGit, held: Set<String> = ["memory/lumalab/look.md"]) -> MemoryHealth.Report {
        MemoryHealth.analyze(MemoryHealth.read(brain: brain, git: git, accountSlugs: ["work", "perso"], held: held))
    }

    func items(_ report: MemoryHealth.Report, _ group: MemoryHealth.GroupID) -> [MemoryHealth.Item] {
        report.groups.first { $0.id == group }?.items ?? []
    }

    // MARK: The scan

    /// The walk the graph uses also lists the project folders, the empty ones included: they are link targets.
    @Test func theScanListsProjectFoldersEvenEmpty() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _) = try ownersLayout(home)
        let scan = MemoryGraphBuilder(root: brain.root).memoryScan()
        #expect(scan.folders == ["acme", "beehive", "brainmerge", "lumalab", "scratch-2026-09-10-5855fd",
                                 "scratch-2026-09-11-343e32", "scratch-2026-09-23-5050ce"])
        #expect(scan.notes.map(\.path).contains("memory/acme/MEMORY.md"))
        #expect(scan.notes.map(\.path).contains("BRAIN.md"))
        #expect(!scan.notes.contains { $0.path.hasPrefix(".git/") || $0.path.hasPrefix(".brainmerge/") })
        #expect(!scan.refused)
    }

    // MARK: Index lines

    /// Both kinds of link line are read, with their line number; code blocks, web links and images are not note links.
    @Test func indexLinesAreMarkdownAndWikiLinks() {
        let text = "# Index\n- [Deploy](deploy.md) how\n- [[pricing|Prices]] and [[tone#Voice]]\n```\n- [Code](code.md)\n```\n- [Site](https://example.com/a.md)\n- ![Logo](logo.png)\r\n- [Deep](sub/deep.md)\n"
        let links = MemoryIndex.links(in: text)
        #expect(links.map(\.line) == [2, 3, 9])
        #expect(links[0].targets == [.markdown("deploy.md")])
        #expect(links[1].targets == [.wiki("pricing"), .wiki("tone")])
        #expect(links[2].targets == [.markdown("sub/deep.md")])
        #expect(links[0].text == "- [Deploy](deploy.md) how")
        #expect(MemoryIndex.lineCount(text) == 9)
        #expect(MemoryIndex.lineCount("one\ntwo") == 2)
        #expect(MemoryIndex.lineCount("") == 0)
        #expect(MemoryIndex.loadedLines == 200)
    }

    // MARK: The report

    @Test func theOwnersLayoutFillsEveryGroup() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try ownersLayout(home)
        let report = report(brain, git)
        #expect(report.groups.map(\.id) == [.notLoaded, .oneOff, .copies, .dangling, .unsaved])
        #expect(report.groups.map(\.title) == ["Notes Claude will not load", "Notes in one-off folders", "Copies left when linking",
                                               "Index lines that point nowhere", "Changes not saved for more than a day"])
        #expect(report.count == 8)
        #expect(report.projects == ["acme", "beehive", "brainmerge", "lumalab"])

        let notLoaded = items(report, .notLoaded)
        #expect(notLoaded.map(\.kind) == [.indexTooLong, .notInIndex, .noIndex])
        #expect(notLoaded[0].sentence == "acme's index has 243 lines. Claude Code loads the first 200.")
        #expect(notLoaded[0].lines == 243 && notLoaded[0].files == ["memory/acme/MEMORY.md"])
        #expect(notLoaded[0].detail == "Named after line 200: prices.md")
        // The copy has its own group and the archive is left alone: only orphan.md is missing.
        #expect(notLoaded[1].sentence == "1 note of acme is missing from its index.")
        #expect(notLoaded[1].files == ["memory/acme/orphan.md"] && notLoaded[1].detail == "orphan.md")
        #expect(notLoaded[2].sentence == "lumalab has 2 notes and no index, so no session loads them.")
        #expect(notLoaded[2].files == ["memory/lumalab/look.md", "memory/lumalab/palette.md"])

        let oneOff = items(report, .oneOff)
        #expect(oneOff.map(\.kind) == [.oneOffNotes, .emptyOneOffFolders])
        #expect(oneOff[0].sentence == "2 notes sit in a quick session's folder that no later session reads.")
        #expect(oneOff[0].project == "scratch-2026-09-23-5050ce" && oneOff[0].detail == "scratch-2026-09-23-5050ce")
        #expect(oneOff[0].files == ["memory/scratch-2026-09-23-5050ce/beehive-gear.md", "memory/scratch-2026-09-23-5050ce/beehive-pricing.md"])
        #expect(oneOff[0].suggested == ["beehive"])
        // An index with no link line is no note: that folder is empty too.
        #expect(oneOff[1].sentence == "2 quick session folders are empty.")
        #expect(oneOff[1].files == ["memory/scratch-2026-09-10-5855fd", "memory/scratch-2026-09-11-343e32"])

        let copies = items(report, .copies)
        #expect(copies.map(\.sentence) == ["acme has two copies of deploy.md."])
        #expect(copies[0].files == ["memory/acme/deploy.md", "memory/acme/deploy.work.md"])
        #expect(copies[0].detail == "deploy.md and deploy.work.md")

        let dangling = items(report, .dangling)
        #expect(dangling.map(\.sentence) == ["acme's index names 1 note that is not there."])
        #expect(dangling[0].detail == "gone.md" && dangling[0].files == ["memory/acme/MEMORY.md"])

        // look.md is held back by the secret guard (its banner says so) and palette.md changed just now.
        let unsaved = items(report, .unsaved)
        #expect(unsaved.map(\.sentence) == ["1 change has not been saved for more than a day."])
        #expect(unsaved[0].files == ["memory/beehive/route.md"])

        // An empty regular project waits for its notes: never listed.
        #expect(!report.groups.flatMap(\.items).contains { $0.project == "brainmerge" })
    }

    /// Hidden folders leave the empty row; a hidden folder that gets a note shows again with it.
    @Test func hiddenFoldersLeaveTheEmptyRow() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try ownersLayout(home)
        try write(#"{"folders":["scratch-2026-09-10-5855fd","scratch-2026-09-23-5050ce"]}"#, ".brainmerge/hidden.json", in: brain)
        let oneOff = items(report(brain, git), .oneOff)
        #expect(oneOff.map(\.sentence) == ["2 notes sit in a quick session's folder that no later session reads.",
                                           "1 quick session folder is empty."])
        #expect(oneOff[1].files == ["memory/scratch-2026-09-11-343e32"])
        #expect(MemoryTidy.hidden(in: brain) == ["scratch-2026-09-10-5855fd", "scratch-2026-09-23-5050ce"])
    }

    /// A tidy memory says nothing, and the words fit one of each.
    @Test func aTidyMemoryHasNothingToSay() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        try write("- [[route]]\n", "memory/beehive/MEMORY.md", in: brain)
        try write("# route\n", "memory/beehive/route.md", in: brain)
        try folder("brainmerge", in: brain)
        let report = report(brain, BrainGit(brain: brain), held: [])
        #expect(report.count == 0 && report.groups.isEmpty)
        #expect(report.projects == ["beehive", "brainmerge"])
    }

    /// Singular sentences, and a list of names that stays short.
    @Test func sentencesCountRight() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        try write("# a\n", "memory/solo/a.md", in: brain)
        try write("# b\n", "memory/scratch-2026-09-24-8ef864/b.md", in: brain)
        try write("- [[x]]\n- [[y]]\n", "memory/many/MEMORY.md", in: brain)
        for name in ["n1", "n2", "n3", "n4", "n5"] { try write("# \(name)\n", "memory/many/\(name).md", in: brain) }
        let all = report(brain, BrainGit(brain: brain), held: []).groups.flatMap(\.items)
        #expect(all.map(\.sentence) == ["5 notes of many are missing from its index.", "solo has 1 note and no index, so no session loads it.",
                                        "1 note sits in a quick session's folder that no later session reads.",
                                        "many's index names 2 notes that are not there."])
        #expect(all[0].detail == "n1.md, n2.md, n3.md and 2 more")
        #expect(all[3].detail == "x, y")
    }

    /// File under suggests the projects a note's name mentions, the most notes first.
    @Test func fileUnderSuggestsProjectsByName() {
        let projects = ["beehive", "field-app", "field-app-docs", "lumalab"]
        #expect(MemoryHealth.suggestions(for: ["memory/s/beehive-pricing.md", "memory/s/project_beehive.md", "memory/s/lumalab notes.md"],
                                         among: projects) == ["beehive", "lumalab"])
        #expect(MemoryHealth.suggestions(for: ["memory/s/field-app-docs-plan.md"], among: projects) == ["field-app-docs", "field-app"])
        #expect(MemoryHealth.suggestions(for: ["memory/s/beehivex.md", "memory/s/notes.md"], among: projects).isEmpty)
    }

    /// The read looks and never writes: git's own index is not even refreshed (a save may be taking it).
    @Test func readingChangesNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try ownersLayout(home)
        // A note touched without a change: a plain `git status` would write git's index to note its new date.
        try age("memory/beehive/MEMORY.md", in: brain, days: 3)
        let index = brain.gitDir.appending(path: "index")
        let before = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        let status = try git.shell.check("/usr/bin/git", ["--no-optional-locks", "status", "--porcelain"], cwd: brain.root)
        _ = report(brain, git)
        #expect(try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date == before)
        #expect(try git.shell.check("/usr/bin/git", ["--no-optional-locks", "status", "--porcelain"], cwd: brain.root) == status)
    }

    /// Without git nothing starts it: the unsaved group is simply missing.
    @Test func withoutGitTheUnsavedGroupIsLeftOut() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _) = try ownersLayout(home)
        let noGit = BrainGit(brain: brain, availability: GitAvailability(shell: Shell { _, _, _, _ in ShellResult(status: 2, stdout: "", stderr: "") }, isExecutable: { _ in false }))
        let report = MemoryHealth.analyze(MemoryHealth.read(brain: brain, git: noGit, accountSlugs: ["work"], held: []))
        #expect(!report.groups.contains { $0.id == .unsaved })
        #expect(report.groups.contains { $0.id == .notLoaded })
    }
}
