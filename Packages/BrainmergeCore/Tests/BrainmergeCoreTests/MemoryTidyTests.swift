import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Tidy's buttons, each one click and one commit as You: File under moves notes with their index lines, Keep this one puts
/// the other copy in `_archive/`, Hide notes empty folders in `.brainmerge/hidden.json`. A note being written or not saved
/// yet is never moved, and no folder is ever deleted.
@Suite struct MemoryTidyTests {
    static let scratch = "scratch-2026-09-23-5050ce"

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ path: String, in brain: Brain) throws -> String {
        try String(contentsOf: brain.root.appending(path: path), encoding: .utf8)
    }

    func exists(_ path: String, in brain: Brain) -> Bool {
        FileManager.default.fileExists(atPath: brain.root.appending(path: path).path)
    }

    /// The paths the last commit changed, a move counted as its two ends.
    func committed(_ git: BrainGit) throws -> Set<String> {
        Set(try git.shell.check("/usr/bin/git", ["-c", "core.quotePath=false", "show", "--no-renames", "--name-only", "--pretty=format:", "HEAD"],
                                cwd: git.brain.root).split(separator: "\n").map(String.init))
    }

    /// Every file of the memory dated an hour ago: nothing is being written.
    func settle(_ brain: Brain) throws {
        let fm = FileManager.default
        let walk = try #require(fm.enumerator(atPath: brain.memoryDir.path))
        while let path = walk.nextObject() as? String {
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: brain.memoryDir.appending(path: path).path)
        }
    }

    /// A quick session's folder with two notes about beehive, its index naming them and a note that is gone; beehive has its
    /// own index and note; acme has a note and the copy an account left when it was linked.
    func memory(_ home: TempHome) throws -> (Brain, BrainGit, MemoryTidy) {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write("- [[route]]\n", "memory/beehive/MEMORY.md", in: brain)
        try write("# route\n", "memory/beehive/route.md", in: brain)
        try write("# Memory\n- [Pricing](beehive-pricing.md) prices\n- [Gear](beehive-gear.md) gear\n- [Elsewhere](gone.md)\n",
                  "memory/\(Self.scratch)/MEMORY.md", in: brain)
        try write("# pricing\n", "memory/\(Self.scratch)/beehive-pricing.md", in: brain)
        try write("# gear\n", "memory/\(Self.scratch)/beehive-gear.md", in: brain)
        try write("- [Deploy](deploy.md)\n", "memory/acme/MEMORY.md", in: brain)
        try write("# deploy, as the memory had it\n", "memory/acme/deploy.md", in: brain)
        try write("# deploy, as Work had it\n", "memory/acme/deploy.work.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        try settle(brain)
        return (brain, git, MemoryTidy(brain: brain, git: git))
    }

    // MARK: File under

    @Test func fileUnderMovesNotesAndTheirIndexLinesInOneCommitAsYou() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(plan.notes == ["memory/\(Self.scratch)/beehive-gear.md", "memory/\(Self.scratch)/beehive-pricing.md"])
        #expect(plan.indexLines == 2)
        #expect(plan.preview == "Move 2 notes from \(Self.scratch) to beehive, with their index lines.")
        // Looking changes nothing.
        #expect(try !git.hasChanges())

        let saved = try tidy.file(plan)
        #expect(saved == ["memory/beehive/MEMORY.md", "memory/beehive/beehive-gear.md", "memory/beehive/beehive-pricing.md",
                          "memory/\(Self.scratch)/MEMORY.md", "memory/\(Self.scratch)/beehive-gear.md", "memory/\(Self.scratch)/beehive-pricing.md"])
        let entries = try git.log(limit: 10)
        #expect(entries.count == 2)
        let last = try #require(entries.first)
        #expect(last.authorName == "You" && last.authorEmail == OwnEdits.author.email)
        #expect(last.message == "You filed 2 notes under beehive")
        #expect(try committed(git) == Set(saved))
        #expect(try read("memory/beehive/beehive-gear.md", in: brain) == "# gear\n")
        #expect(!exists("memory/\(Self.scratch)/beehive-gear.md", in: brain))
        // The lines move as they were written, in their order; the line to nothing stays where it was.
        #expect(try read("memory/beehive/MEMORY.md", in: brain) == "- [[route]]\n- [Pricing](beehive-pricing.md) prices\n- [Gear](beehive-gear.md) gear\n")
        #expect(try read("memory/\(Self.scratch)/MEMORY.md", in: brain) == "# Memory\n- [Elsewhere](gone.md)\n")
        // The folder stays: accounts link to it.
        #expect(exists("memory/\(Self.scratch)", in: brain))
        #expect(try !git.hasChanges())
    }

    /// A project without an index gets one holding the moved lines; a note with no line moves alone.
    @Test func fileUnderStartsAnIndexWhenThereIsNone() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try FileManager.default.createDirectory(at: brain.memoryDir(forProject: "lumalab"), withIntermediateDirectories: true)
        let plan = try tidy.plan(filing: Self.scratch, under: "lumalab")
        try tidy.file(plan)
        #expect(try read("memory/lumalab/MEMORY.md", in: brain) == "- [Pricing](beehive-pricing.md) prices\n- [Gear](beehive-gear.md) gear\n")
        #expect(try git.log(limit: 1).first?.message == "You filed 2 notes under lumalab")

        try write("# alone\n", "memory/scratch-2026-09-24-8ef864/alone.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "More")
        try settle(brain)
        let single = try tidy.plan(filing: "scratch-2026-09-24-8ef864", under: "lumalab")
        #expect(single.preview == "Move 1 note from scratch-2026-09-24-8ef864 to lumalab.")
        try tidy.file(single)
        #expect(try git.log(limit: 1).first?.message == "You filed a note under lumalab")
        #expect(exists("memory/lumalab/alone.md", in: brain) && exists("memory/scratch-2026-09-24-8ef864", in: brain))
    }

    /// A note written in the last two minutes, or an index being written, is never moved.
    @Test func aNoteChangedInTheLastTwoMinutesIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: brain.root.appending(path: "memory/beehive/MEMORY.md").path)
        #expect(throws: BrainmergeError.noteBeingWritten) { try tidy.file(plan) }
        #expect(BrainmergeError.noteBeingWritten.description == "This note is being written. Try again in a moment.")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90)],
                                              ofItemAtPath: brain.root.appending(path: "memory/\(Self.scratch)/beehive-gear.md").path)
        #expect(throws: BrainmergeError.noteBeingWritten) { try tidy.file(plan) }
        #expect(exists("memory/\(Self.scratch)/beehive-gear.md", in: brain))
        #expect(try git.log(limit: 10).count == 1)
    }

    /// A note that changed since the preview (a session wrote another one there) is not moved on the old plan.
    @Test func aFolderThatChangedSinceThePreviewIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        try write("# more\n", "memory/\(Self.scratch)/beehive-more.md", in: brain)
        try git.commitAll(authorName: "Work", authorEmail: "work@brainmerge.local", message: "Work remembered something")
        try settle(brain)
        #expect(throws: BrainmergeError.noteBeingWritten) { try tidy.file(plan) }
        #expect(try git.log(limit: 10).count == 2)
    }

    /// A note with changes no save has committed yet stays: moving it would sign someone else's words as yours.
    @Test func aNoteNotSavedYetIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try write("# gear, rewritten\n", "memory/\(Self.scratch)/beehive-gear.md", in: brain)
        try settle(brain)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(throws: BrainmergeError.noteNotSaved) { try tidy.file(plan) }
        #expect(try read("memory/\(Self.scratch)/beehive-gear.md", in: brain) == "# gear, rewritten\n")
        #expect(try git.log(limit: 10).count == 1)
    }

    /// A session adds a line to an index while the notes move: nothing overwrites it. File under stops, the notes go back
    /// and the session's line stays; nothing is committed.
    @Test func anIndexWrittenDuringTheMoveIsKept() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        let target = brain.root.appending(path: "memory/beehive/MEMORY.md")
        var racing = tidy
        racing.beforeIndexWrite = { try? Data("- [[route]]\n- [[fresh]]\n".utf8).write(to: target) }
        #expect(throws: BrainmergeError.noteBeingWritten) { try racing.file(plan) }
        #expect(try read("memory/beehive/MEMORY.md", in: brain) == "- [[route]]\n- [[fresh]]\n")
        #expect(exists("memory/\(Self.scratch)/beehive-gear.md", in: brain) && !exists("memory/beehive/beehive-gear.md", in: brain))
        #expect(try read("memory/\(Self.scratch)/MEMORY.md", in: brain).contains("beehive-gear.md"))
        #expect(try git.log(limit: 10).count == 1)
    }

    /// An index that is a link (to a file outside the memory, maybe with keys in it) is never read, replaced or committed.
    @Test func aLinkedIndexIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let outside = home.url.appending(path: "credentials")
        try Data("key = secret\n".utf8).write(to: outside)
        let target = brain.root.appending(path: "memory/beehive/MEMORY.md")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Link")
        try settle(brain)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(throws: BrainmergeError.indexIsALink(project: "beehive")) { try tidy.file(plan) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == outside.path)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "key = secret\n")
        #expect(exists("memory/\(Self.scratch)/beehive-gear.md", in: brain))
        #expect(try git.log(limit: 10).count == 2)
    }

    /// A note of the same name already in the project: nothing moves.
    @Test func aNameTakenInTheProjectIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try write("# gear here\n", "memory/beehive/beehive-gear.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "More")
        try settle(brain)
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(throws: BrainmergeError.noteExists(name: "beehive-gear.md", project: "beehive")) { try tidy.file(plan) }
        #expect(exists("memory/\(Self.scratch)/beehive-pricing.md", in: brain))
        #expect(try git.log(limit: 10).count == 2)
    }

    /// Your own git stopped half way: nothing moves until you finish.
    @Test func anUnfinishedMergeIsWaitedFor() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        let head = try #require(git.head())
        try Data((head + "\n").utf8).write(to: brain.gitDir.appending(path: "MERGE_HEAD"))
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(throws: BrainmergeError.gitOperationUnfinished) { try tidy.file(plan) }
        #expect(exists("memory/\(Self.scratch)/beehive-gear.md", in: brain))
    }

    /// When the commit fails, every note and line goes back where it was.
    @Test func aFailedCommitPutsEverythingBack() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, _) = try memory(home)
        // Git refuses the commit (a full disk, say). A hook cannot stand for it: none runs in a save.
        let tidy = MemoryTidy(brain: brain, git: BrainGit(brain: brain, shell: Shell { executable, arguments, cwd, environment in
            guard arguments.contains("commit") || arguments.contains("commit-tree") else {
                return try Shell().run(executable, arguments, cwd: cwd, environment: environment)
            }
            return ShellResult(status: 128, stdout: "", stderr: "fatal: unable to write commit")
        }))
        let plan = try tidy.plan(filing: Self.scratch, under: "beehive")
        #expect(throws: (any Error).self) { try tidy.file(plan) }
        #expect(exists("memory/\(Self.scratch)/beehive-gear.md", in: brain) && !exists("memory/beehive/beehive-gear.md", in: brain))
        #expect(try read("memory/beehive/MEMORY.md", in: brain) == "- [[route]]\n")
        #expect(try read("memory/\(Self.scratch)/MEMORY.md", in: brain).contains("beehive-gear.md"))
        #expect(try !git.hasChanges())
        #expect(try git.log(limit: 10).count == 1)
    }

    // MARK: Keep this one

    @Test func keepingTheMemorysCopyArchivesTheAccountsCopy() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try tidy.keep("memory/acme/deploy.md", over: "memory/acme/deploy.work.md")
        #expect(try read("memory/acme/deploy.md", in: brain) == "# deploy, as the memory had it\n")
        #expect(try read("memory/acme/_archive/deploy.work.md", in: brain) == "# deploy, as Work had it\n")
        #expect(!exists("memory/acme/deploy.work.md", in: brain))
        let last = try #require(try git.log(limit: 1).first)
        #expect(last.authorName == "You" && last.message == "You kept one copy of deploy.md")
        #expect(try committed(git) == ["memory/acme/deploy.work.md", "memory/acme/_archive/deploy.work.md"])
        #expect(try !git.hasChanges())
    }

    /// The account's copy kept takes the note's name, so the index still finds it; the other one goes to the archive.
    @Test func keepingTheAccountsCopyGivesItTheNotesName() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try write("# an older archive\n", "memory/acme/_archive/deploy.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "More")
        try settle(brain)
        try tidy.keep("memory/acme/deploy.work.md", over: "memory/acme/deploy.md")
        #expect(try read("memory/acme/deploy.md", in: brain) == "# deploy, as Work had it\n")
        #expect(try read("memory/acme/_archive/deploy-2.md", in: brain) == "# deploy, as the memory had it\n")
        #expect(try read("memory/acme/_archive/deploy.md", in: brain) == "# an older archive\n")
        #expect(!exists("memory/acme/deploy.work.md", in: brain))
        #expect(try git.log(limit: 1).first?.message == "You kept one copy of deploy.md")
        #expect(try !git.hasChanges())
    }

    @Test func keepRefusesACopyBeingWritten() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: brain.root.appending(path: "memory/acme/deploy.work.md").path)
        #expect(throws: BrainmergeError.noteBeingWritten) { try tidy.keep("memory/acme/deploy.md", over: "memory/acme/deploy.work.md") }
        #expect(exists("memory/acme/deploy.work.md", in: brain))
        #expect(try git.log(limit: 10).count == 1)
    }

    // MARK: Hide

    @Test func hideNotesTheFoldersAndKeepsThem() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        for name in ["scratch-2026-09-10-5855fd", "scratch-2026-09-11-343e32"] {
            try FileManager.default.createDirectory(at: brain.memoryDir(forProject: name), withIntermediateDirectories: true)
        }
        try tidy.hide(["scratch-2026-09-10-5855fd"])
        #expect(MemoryTidy.hidden(in: brain) == ["scratch-2026-09-10-5855fd"])
        #expect(try git.log(limit: 1).first?.message == "You hid an empty folder from Tidy")
        #expect(try committed(git) == [".brainmerge/hidden.json"])
        try tidy.hide(["scratch-2026-09-11-343e32", "scratch-2026-09-10-5855fd"])
        #expect(MemoryTidy.hidden(in: brain) == ["scratch-2026-09-10-5855fd", "scratch-2026-09-11-343e32"])
        #expect(try git.log(limit: 1).first?.message == "You hid an empty folder from Tidy")
        // Nothing new to hide: no commit.
        #expect(try tidy.hide(["scratch-2026-09-10-5855fd"]).isEmpty)
        #expect(try git.log(limit: 10).count == 3)
        #expect(exists("memory/scratch-2026-09-10-5855fd", in: brain) && exists("memory/scratch-2026-09-11-343e32", in: brain))
        #expect(Brain.ownEditsScope.contains(".brainmerge/hidden.json"))
    }

    /// Hiding many folders at once is one commit.
    @Test func hidingSeveralIsOneCommit() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, tidy) = try memory(home)
        try tidy.hide(["scratch-a", "scratch-b", "scratch-c"])
        #expect(try git.log(limit: 1).first?.message == "You hid 3 empty folders from Tidy")
        #expect(MemoryTidy.hidden(in: brain).count == 3)
    }
}
