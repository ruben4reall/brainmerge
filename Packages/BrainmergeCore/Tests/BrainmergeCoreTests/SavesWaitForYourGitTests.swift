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

    /// A clean merge left open with --no-commit is seen whatever way the memory's folder was written: git names its
    /// markers relative to the folder, and a folder URL without a trailing slash must not resolve them in its parent.
    @Test func aMergeLeftOpenIsSeenFromAFolderWrittenWithoutASlash() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _) = try diverged(home)
        try git(["reset", "-q", "--hard", "HEAD~1"], in: brain)
        #expect(try git(["merge", "-q", "--no-commit", "--no-ff", "other"], in: brain).status == 0)
        #expect(exists("MERGE_HEAD", in: brain))
        let bare = Brain(root: URL(filePath: brain.root.path.hasSuffix("/") ? String(brain.root.path.dropLast()) : brain.root.path, directoryHint: .notDirectory))
        #expect(!bare.root.hasDirectoryPath, "the case under test: a folder URL with no trailing slash")
        #expect(try BrainGit(brain: bare).operationUnfinished())
        #expect(try BrainGit(brain: brain).operationUnfinished())
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

    /// Each of git's stopped states is seen without a conflict too, where the index alone shows nothing: a pick resolved
    /// but not continued, a revert left open, a rebase stopped by its own step, `git am` stopped, a bisect under way.
    @Test(arguments: ["cherry-pick", "revert", "rebase", "am", "bisect"])
    func aSaveWaitsWhileYourGitIsStoppedWithoutAConflict(_ operation: String) throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        let marker: String
        switch operation {
        case "cherry-pick":
            #expect(try git(["cherry-pick", "other"], in: brain).status != 0)
            try write("both\n", "memory/acme/old.md", in: brain)
            try git(["add", "memory/acme/old.md"], in: brain)
            marker = "CHERRY_PICK_HEAD"
        case "revert":
            #expect(try git(["revert", "--no-commit", "HEAD"], in: brain).status == 0)
            marker = "REVERT_HEAD"
        case "rebase":
            #expect(try git(["rebase", "-x", "false", "HEAD~1"], in: brain).status != 0)
            marker = "rebase-merge"
        case "am":
            // `other`'s commit, which does not apply over main's: am stops before changing anything.
            let patch = home.url.appending(path: "theirs.mbox")
            try Data(try git(["format-patch", "-1", "--stdout", "other"], in: brain).stdout.utf8).write(to: patch)
            #expect(try git(["am", patch.path], in: brain).status != 0)
            marker = "rebase-apply"
        default:
            #expect(try git(["bisect", "start"], in: brain).status == 0)
            marker = "BISECT_LOG"
        }
        #expect(try git(["ls-files", "-u"], in: brain).stdout.isEmpty, "no conflict in the index")
        #expect(exists(marker, in: brain))
        let head = repo.head()
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(repo.head() == head)
        #expect(exists(marker, in: brain), "the person can still finish or abort it")
    }

    /// A commit checked out to look at it, on no branch: a save there would be on no branch, and its notes would go at the
    /// next checkout. It waits until a branch is checked out again.
    @Test func aSaveWaitsWhileNoBranchIsCheckedOut() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, repo) = try diverged(home)
        try git(["checkout", "-q", "--detach", "HEAD~1"], in: brain)
        let head = repo.head()
        try accountWrote(brain)

        #expect(throws: BrainmergeError.gitOperationUnfinished) { try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work) }
        #expect(repo.head() == head)
        #expect(TouchedLedger.claimed(in: brain) == ["memory/acme/note.md"])

        try git(["checkout", "-q", "main"], in: brain)
        #expect(try AccountSave(brain: brain, git: repo, held: held(home)).run(for: work).saved == ["memory/acme/note.md"])
        #expect(try git(["log", "-1", "--format=%an", "main", "--", "memory/acme/note.md"], in: brain).stdout == "Work\n")
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
                == "Git is in the middle of a merge, rebase or cherry-pick in this memory, or no branch is checked out. Saves wait until you finish it.")
    }
}

/// Another git (an editor's, Obsidian Git's status check) may hold the real index right when a save ends. The save is
/// made either way, and the real index catches up with it: a plain `git commit` of yours never undoes an account's save.
@Suite struct AnotherGitHoldsTheIndexTests {
    let work = Identity(slug: "work", name: "Work", tint: .blue)

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func memory(_ home: TempHome) throws -> Brain {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try BrainGit(brain: brain).commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        return brain
    }

    func held(_ home: TempHome) -> HeldStore { HeldStore(paths: home.paths, memoryID: "shared") }
    func lock(_ brain: Brain) -> URL { brain.gitDir.appending(path: "index.lock") }

    /// What a plain `git commit` of yours would commit now: the real index against the last commit.
    func yourNextCommit(_ brain: Brain) throws -> String {
        try Shell().check("/usr/bin/git", ["diff", "--cached", "--name-only"], cwd: brain.root)
    }

    /// Right after the save's commit (the branch moved to it), another git takes the real index, and lets go after
    /// `release` seconds, or never.
    func busyIndexGit(_ brain: Brain, release: TimeInterval?) -> BrainGit {
        let lock = lock(brain)
        return BrainGit(brain: brain, shell: Shell { executable, arguments, cwd, environment in
            let result = try Shell().run(executable, arguments, cwd: cwd, environment: environment)
            if arguments.first == "update-ref", result.status == 0 {
                FileManager.default.createFile(atPath: lock.path, contents: nil)
                // A thread of its own: a busy dispatch pool would let go late.
                if let release { Thread.detachNewThread { Thread.sleep(forTimeInterval: release); try? FileManager.default.removeItem(at: lock) } }
            }
            return result
        })
    }

    func accountWrote(_ path: String, in brain: Brain) throws {
        try write("# \(path)\n", path, in: brain)
        try TouchedLedger(brain: brain, slug: "work").append(path)
    }

    @Test func aBriefHoldIsWaitedFor() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        let git = busyIndexGit(brain, release: 0.15)
        try accountWrote("memory/acme/old.md", in: brain)

        #expect(try AccountSave(brain: brain, git: git, held: held(home)).run(for: work).saved == ["memory/acme/old.md"])
        #expect(try yourNextCommit(brain).isEmpty)
        #expect(git.indexBehind.isEmpty)
    }

    @Test func aHoldThatLastsNeverFailsTheSave() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        let git = busyIndexGit(brain, release: nil)
        try accountWrote("memory/acme/old.md", in: brain)

        #expect(try AccountSave(brain: brain, git: git, held: held(home)).run(for: work).saved == ["memory/acme/old.md"])
        #expect(try git.log(limit: 1).first?.authorName == "Work")
        #expect(TouchedLedger.claimed(in: brain).isEmpty, "the note is saved: it is not saved again")
        #expect(git.indexBehind == ["memory/acme/old.md"])

        // Once the other git let go, the real index catches up.
        try FileManager.default.removeItem(at: lock(brain))
        try BrainGit(brain: brain).catchUpIndex()
        #expect(try yourNextCommit(brain).isEmpty)
        #expect(git.indexBehind.isEmpty)
    }

    @Test func theNextSaveCatchesUp() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        try accountWrote("memory/acme/old.md", in: brain)
        _ = try AccountSave(brain: brain, git: busyIndexGit(brain, release: nil), held: held(home)).run(for: work)
        try FileManager.default.removeItem(at: lock(brain))

        try accountWrote("memory/acme/new.md", in: brain)
        let git = BrainGit(brain: brain)
        #expect(try AccountSave(brain: brain, git: git, held: held(home)).run(for: work).saved == ["memory/acme/new.md"])
        #expect(try yourNextCommit(brain).isEmpty)
        #expect(git.indexBehind.isEmpty)
    }

    /// An account's turn that ends with nothing to save catches up too: the index is not left behind until that
    /// account writes again.
    @Test func aSaveWithNothingToSaveCatchesUp() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        try accountWrote("memory/acme/old.md", in: brain)
        _ = try AccountSave(brain: brain, git: busyIndexGit(brain, release: nil), held: held(home)).run(for: work)
        try FileManager.default.removeItem(at: lock(brain))

        let git = BrainGit(brain: brain)
        #expect(try AccountSave(brain: brain, git: git, held: held(home)).run(for: work).saved.isEmpty)
        #expect(try yourNextCommit(brain).isEmpty)
        #expect(git.indexBehind.isEmpty)
    }

    /// The app's minute pass catches up too, whether or not it saves anything.
    @Test func theAppsPassCatchesUp() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        try accountWrote("memory/acme/old.md", in: brain)
        _ = try AccountSave(brain: brain, git: busyIndexGit(brain, release: nil), held: held(home)).run(for: work)
        try FileManager.default.removeItem(at: lock(brain))

        let git = BrainGit(brain: brain)
        #expect(try OwnEdits(brain: brain, git: git, held: held(home)).save(now: Date(), sessionRunning: true) == .sessionRunning)
        #expect(try yourNextCommit(brain).isEmpty)
        #expect(git.indexBehind.isEmpty)
    }

    /// A path you staged yourself, never saved by an account, is not touched.
    @Test func catchingUpLeavesWhatYouStaged() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try memory(home)
        try accountWrote("memory/acme/old.md", in: brain)
        _ = try AccountSave(brain: brain, git: busyIndexGit(brain, release: nil), held: held(home)).run(for: work)
        try FileManager.default.removeItem(at: lock(brain))
        try write("# mine\n", "Journal.md", in: brain)
        try Shell().check("/usr/bin/git", ["add", "Journal.md"], cwd: brain.root)

        try BrainGit(brain: brain).catchUpIndex()
        #expect(try yourNextCommit(brain) == "Journal.md\n")
    }
}
