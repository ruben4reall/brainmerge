import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// A save never finishes the person's own git work. While a merge, a cherry-pick, a rebase or a stash pop is stopped on a
/// conflict, every save waits: nothing is committed, what the person was doing stays as it was, and the account's list
/// keeps its paths for the save after.
@Suite struct SavesWaitForYourGitTests {
    let work = Identity(slug: "work", name: "Work", tint: .blue)

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The person's own git, as `name`.
    @discardableResult
    func git(_ arguments: [String], as name: String = "Here", in brain: Brain) throws -> ShellResult {
        try Shell().run("/usr/bin/git", ["-c", "user.name=\(name)", "-c", "user.email=\(name.lowercased())@example.com",
                                         "-c", "commit.gpgsign=false"] + arguments, cwd: brain.root)
    }

    /// `memory/acme/old.md` changed one way on main, by Here, and the other way on `other`, by Remote.
    func diverged(_ home: TempHome) throws -> (Brain, BrainGit) {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let repo = BrainGit(brain: brain)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try repo.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        try git(["checkout", "-q", "-b", "other"], in: brain)
        try write("theirs\n", "memory/acme/old.md", in: brain)
        try git(["commit", "-q", "-am", "Theirs"], as: "Remote", in: brain)
        try git(["checkout", "-q", "main"], in: brain)
        try write("ours\n", "memory/acme/old.md", in: brain)
        try git(["commit", "-q", "-am", "Ours"], in: brain)
        return (brain, repo)
    }

    func held(_ home: TempHome) -> HeldStore { HeldStore(paths: home.paths, memoryID: "shared") }

    func exists(_ name: String, in brain: Brain) -> Bool {
        FileManager.default.fileExists(atPath: brain.gitDir.appending(path: name).path)
    }

    /// An account's note waiting on its list.
    func accountWrote(_ brain: Brain) throws {
        try write("# note\n", "memory/acme/note.md", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/note.md")
    }

    @Test func aSaveWaitsWhileYourMergeIsStopped() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        #expect(try git(["merge", "-q", "other"], in: brain).status != 0)
        let head = repo.head()
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(repo.head() == head, "no merge commit is made in the account's name")
        #expect(exists("MERGE_HEAD", in: brain), "the person can still abort the merge")
        #expect(TouchedLedger.claimed(in: brain) == ["memory/acme/note.md"])

        // Once the person is done, the note is saved.
        #expect(try git(["merge", "--abort"], in: brain).status == 0)
        #expect(try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work).saved == ["memory/acme/note.md"])
    }

    @Test func aSaveIsNeverSignedByTheCommitYouArePicking() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        #expect(try git(["cherry-pick", "other"], in: brain).status != 0)
        let head = repo.head()
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(repo.head() == head)
        #expect(exists("CHERRY_PICK_HEAD", in: brain))
        #expect(try repo.log(limit: 10).allSatisfy { $0.authorName != "Remote" })
    }

    @Test func aSaveWaitsWhileYourRebaseIsStopped() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        #expect(try git(["rebase", "other"], in: brain).status != 0)
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(exists("rebase-merge", in: brain))
        #expect(TouchedLedger.claimed(in: brain) == ["memory/acme/note.md"])
    }

    /// A stash pop stopped on a conflict leaves no marker file, only conflicted entries in the index.
    @Test func aSaveWaitsWhileAStashPopIsConflicted() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let repo = BrainGit(brain: brain)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try repo.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        try write("stashed\n", "memory/acme/old.md", in: brain)
        try git(["stash", "-q"], in: brain)
        try write("ours\n", "memory/acme/old.md", in: brain)
        try git(["commit", "-q", "-am", "Ours"], in: brain)
        #expect(try git(["stash", "pop"], in: brain).status != 0)
        #expect(!exists("MERGE_HEAD", in: brain))
        let head = repo.head()
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(repo.head() == head)
    }

    /// Ten quiet minutes into a stopped merge, your edits still wait: the conflict markers are never saved as You.
    @Test func yourEditsNeverSaveConflictMarkers() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        #expect(try git(["merge", "-q", "other"], in: brain).status != 0)
        let head = repo.head()
        let edits = OwnEdits(brain: brain, git: repo, held: held(home))

        #expect(throws: BrainmergeError.gitOperationUnfinished) {
            try edits.save(now: Date().addingTimeInterval(OwnEdits.quietPeriod + 60), sessionRunning: false)
        }
        #expect(repo.head() == head)
        #expect(try repo.shell.check("/usr/bin/git", ["show", "HEAD:memory/acme/old.md"], cwd: brain.root) == "ours\n")
        #expect(exists("MERGE_HEAD", in: brain))
    }

    /// The sentence says why the save waits, and nothing of the notes.
    @Test func theSentenceSaysSavesWait() {
        #expect(BrainmergeError.gitOperationUnfinished.description
                == "Git is in the middle of a merge, rebase or cherry-pick in this memory. Saves wait until you finish it.")
    }
}
