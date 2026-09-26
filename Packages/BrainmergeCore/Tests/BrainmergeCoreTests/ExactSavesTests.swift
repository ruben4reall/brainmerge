import CryptoKit
import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Each account commits only what it wrote; the person's own edits are saved as You, later and only when no session runs;
/// nothing outside the memory's own files is ever committed.
@Suite struct ExactSavesTests {
    let work = Identity(slug: "work", name: "Work", tint: .blue)
    let perso = Identity(slug: "perso", name: "Perso", tint: .orange, isPrimary: true)

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A memory with a first commit, like one that has been in use.
    func memory(_ home: TempHome) throws -> (Brain, BrainGit) {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        return (brain, git)
    }

    /// Where held notes go: beside the memory's temporary home.
    func held(_ brain: Brain) -> HeldStore { HeldStore(paths: Paths(home: brain.root.deletingLastPathComponent()), memoryID: "shared") }

    func tracked(_ git: BrainGit) throws -> [String] {
        try git.shell.check("/usr/bin/git", ["-c", "core.quotePath=false", "ls-files"], cwd: git.brain.root)
            .split(separator: "\n").map(String.init)
    }

    @Test func eachAccountCommitsOnlyWhatItWrote() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("# deploy\n", "memory/acme/deploy.md", in: brain)
        try write("# prices\n", "memory/acme/prices.md", in: brain)
        try write("# kayak\n", "memory/kayak/MEMORY.md", in: brain)
        try FileManager.default.removeItem(at: brain.root.appending(path: "memory/acme/old.md"))
        // An Obsidian vault's own files and the person's daily note sit next to the notes.
        try write("# today\n", "Daily/2026-09-25.md", in: brain)
        try write("{}", ".obsidian/workspace.json", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/deploy.md")
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/prices.md")
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/old.md")
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/deploy.md")
        try TouchedLedger(brain: brain, slug: "perso").append("memory/kayak/MEMORY.md")

        let saved = try AccountSave(brain: brain, git: git, held: held(brain)).run(for: work).saved
        #expect(saved == ["memory/acme/deploy.md", "memory/acme/old.md", "memory/acme/prices.md"])
        let last = try #require(try git.log(limit: 1).first)
        #expect(last.authorName == "Work" && last.authorEmail == "work@brainmerge.local")
        #expect(last.message == "Work remembered 3 things about acme")
        #expect(Set(last.files) == ["memory/acme/deploy.md", "memory/acme/prices.md", "memory/acme/old.md"])
        let files = try tracked(git)
        #expect(!files.contains("memory/acme/old.md"), "a deleted note is committed as deleted")
        #expect(!files.contains("memory/kayak/MEMORY.md"), "the other account's note waits for its own save")
        #expect(!files.contains("Daily/2026-09-25.md") && !files.contains(".obsidian/workspace.json"))
        #expect(TouchedLedger.claimed(in: brain) == ["memory/kayak/MEMORY.md"])

        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: perso).saved == ["memory/kayak/MEMORY.md"])
        #expect(try git.log(limit: 1).first?.authorName == "Perso")
        #expect(try git.log(limit: 1).first?.message == "Perso updated its notes about kayak")
        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: perso).saved == [])
        #expect(try git.log(limit: 10).count == 3)
        #expect(!(try tracked(git)).contains { $0.hasPrefix(".brainmerge/touched") })
    }

    /// A path written and then put back as it was, or never there, changes nothing: no empty commit, no error.
    @Test func aPathWithNothingToSaveIsSkipped() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/old.md")
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/never-there.md")
        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: work).saved == [])
        #expect(try git.log(limit: 10).count == 1)
        #expect(TouchedLedger.claimed(in: brain).isEmpty)
    }

    /// Only the given paths are committed, even when the person staged something else by hand.
    @Test func whatThePersonStagedIsLeftStaged() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("# mine\n", "Journal.md", in: brain)
        try git.shell.check("/usr/bin/git", ["add", "Journal.md"], cwd: brain.root)
        try write("# note\n", "memory/acme/note.md", in: brain)
        #expect(try git.commit(paths: ["memory/acme/note.md"], author: work.gitAuthor) { MemorySentence.message(name: "Work", files: $0) } == ["memory/acme/note.md"])
        #expect(try git.log(limit: 1).first?.files == ["memory/acme/note.md"])
        let staged = try git.shell.check("/usr/bin/git", ["diff", "--cached", "--name-only"], cwd: brain.root)
        #expect(staged.trimmingCharacters(in: .whitespacesAndNewlines) == "Journal.md")
    }

    /// A save moves nothing but the branch: no ORIG_HEAD, no reset in HEAD's log, only commits.
    @Test func aSaveLeavesNoTraceButItsCommit() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("# note\n", "memory/acme/note.md", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/note.md")
        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: work).saved == ["memory/acme/note.md"])
        #expect(!FileManager.default.fileExists(atPath: brain.gitDir.appending(path: "ORIG_HEAD").path))
        let reflog = try git.shell.check("/usr/bin/git", ["reflog", "--format=%gs"], cwd: brain.root)
        #expect(reflog.split(separator: "\n").allSatisfy { $0.hasPrefix("commit") }, "\(reflog)")
    }

    /// Another program commits in the memory while a save is being made (the person's git, Obsidian Git): its commit is
    /// kept, and the save goes on top of it instead of taking its notes out.
    @Test func aCommitThatLandsDuringASaveIsKept() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _) = try memory(home)
        let once = FirstTime()
        let git = BrainGit(brain: brain, shell: Shell { executable, arguments, cwd, environment in
            let result = try Shell().run(executable, arguments, cwd: cwd, environment: environment)
            if arguments.contains("add"), once.now() {
                try Data("# pulled\n".utf8).write(to: brain.root.appending(path: "memory/acme/pulled.md"))
                try Shell().check("/usr/bin/git", ["add", "memory/acme/pulled.md"], cwd: brain.root)
                try Shell().check("/usr/bin/git", ["-c", "user.name=Here", "-c", "user.email=here@example.com", "commit", "-q", "-m", "Pulled"],
                                  cwd: brain.root)
            }
            return result
        })
        try write("# note\n", "memory/acme/note.md", in: brain)
        #expect(try git.commit(paths: ["memory/acme/note.md"], author: work.gitAuthor) { _ in "Work saved" } == ["memory/acme/note.md"])
        let log = try git.log(limit: 3)
        #expect(log.map(\.message) == ["Work saved", "Pulled", "Start"])
        #expect(log.first?.files == ["memory/acme/note.md"])
        let saved = try git.shell.check("/usr/bin/git", ["ls-tree", "-r", "--name-only", "HEAD"], cwd: brain.root)
        #expect(saved.split(separator: "\n").contains("memory/acme/pulled.md"), "the other program's note is still saved")
    }

    /// While a save is made, another program commits and the person checks that commit out to look at it, on no branch.
    /// The save's next try sees it and waits, instead of landing on no branch where its notes would go at the next checkout.
    @Test func aSaveTriedAgainAfterACheckoutOnNoBranchWaits() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _) = try memory(home)
        let once = FirstTime()
        let git = BrainGit(brain: brain, shell: Shell { executable, arguments, cwd, environment in
            let result = try Shell().run(executable, arguments, cwd: cwd, environment: environment)
            if arguments.contains("add"), once.now() {
                try Data("# pulled\n".utf8).write(to: brain.root.appending(path: "memory/acme/pulled.md"))
                try Shell().check("/usr/bin/git", ["add", "memory/acme/pulled.md"], cwd: brain.root)
                try Shell().check("/usr/bin/git", ["-c", "user.name=Here", "-c", "user.email=here@example.com", "commit", "-q", "-m", "Pulled"],
                                  cwd: brain.root)
                try Shell().check("/usr/bin/git", ["checkout", "-q", "--detach", "HEAD"], cwd: brain.root)
            }
            return result
        })
        try write("# note\n", "memory/acme/note.md", in: brain)
        #expect(throws: BrainmergeError.gitOperationUnfinished) {
            try git.commit(paths: ["memory/acme/note.md"], author: work.gitAuthor) { _ in "Work saved" }
        }
        let real = Shell()
        #expect(try real.run("/usr/bin/git", ["symbolic-ref", "-q", "HEAD"], cwd: brain.root).status != 0, "still on no branch")
        #expect(try real.check("/usr/bin/git", ["rev-parse", "HEAD"], cwd: brain.root) == real.check("/usr/bin/git", ["rev-parse", "main"], cwd: brain.root))
        let subjects = try real.check("/usr/bin/git", ["log", "--all", "--format=%s"], cwd: brain.root)
        #expect(subjects == "Pulled\nStart\n", "no save on a branch, or on no branch")
    }

    /// Each save leaves its objects loose, one file each, as a commit of yours does. Past the memory's own `gc.auto`, git
    /// packs them after the save, as after a commit of yours: loose objects no longer pile up without end.
    @Test func gitPacksAMemoryAfterSaves() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        // The lowest threshold: git guesses how many loose objects there are from `objects/17` alone, and packs past one.
        try git.shell.check("/usr/bin/git", ["config", "gc.auto", "1"], cwd: brain.root)
        let packs = {
            try FileManager.default.contentsOfDirectory(atPath: brain.gitDir.appending(path: "objects/pack").path).filter { $0.hasSuffix(".pack") }
        }
        #expect(try packs().isEmpty)
        for n in 0..<3 {
            let path = "memory/acme/note\(n).md"
            try write(Self.textStoredIn17(n), path, in: brain)
            #expect(try git.commit(paths: [path], author: work.gitAuthor) { _ in "Work saved \(n)" } == [path])
        }
        #expect(try !packs().isEmpty, "git packed the memory after a save")
        #expect(try git.log(limit: 10).map(\.message) == ["Work saved 2", "Work saved 1", "Work saved 0", "Start"])
        #expect(try git.shell.run("/usr/bin/git", ["fsck", "--no-progress"], cwd: brain.root).status == 0)
    }

    /// A note's text whose object git stores in `objects/17`, the one folder `git gc --auto` counts.
    static func textStoredIn17(_ n: Int) -> String {
        var attempt = 0
        while true {
            let text = "# note \(n), try \(attempt)\n"
            if Array(Insecure.SHA1.hash(data: Data("blob \(text.utf8.count)\0\(text)".utf8))).first == 0x17 { return text }
            attempt += 1
        }
    }

    /// A path whose content is the last commit's (staged by hand, then put back on disk) is not saved: no empty commit,
    /// no error, and what the person staged stays staged.
    @Test func aPathBackToTheLastCommitIsNotSaved() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("# changed\n", "memory/acme/old.md", in: brain)
        try git.shell.check("/usr/bin/git", ["add", "memory/acme/old.md"], cwd: brain.root)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/old.md")
        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: work).saved == [])
        #expect(try git.log(limit: 10).count == 1)
        let staged = try git.shell.check("/usr/bin/git", ["diff", "--cached", "--name-only"], cwd: brain.root)
        #expect(staged == "memory/acme/old.md\n")
    }

    /// Names are taken literally: a note called like a pattern commits itself, not its neighbors.
    @Test func pathsAreLiteral() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("a\n", "memory/acme/*.md", in: brain)
        try write("b\n", "memory/acme/other.md", in: brain)
        try write("c\n", "memory/acme/décision prix.md", in: brain)
        #expect(try git.commit(paths: ["memory/acme/*.md", "memory/acme/décision prix.md"], author: work.gitAuthor) { _ in "m" }
                == ["memory/acme/*.md", "memory/acme/décision prix.md"])
        #expect(!(try tracked(git)).contains("memory/acme/other.md"))
    }

    /// The very first save of a new memory works too (no commit yet).
    @Test func theFirstSaveOfANewMemory() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write("# note\n", "memory/acme/note.md", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/note.md")
        #expect(try AccountSave(brain: brain, git: git, held: held(brain)).run(for: work).saved == ["memory/acme/note.md"])
        #expect(try tracked(git) == ["memory/acme/note.md"])
    }

    @Test func statusListsChangesInsideTheScopeOnly() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git) = try memory(home)
        try write("x\n", "memory/acme/new/deep.md", in: brain)
        try write("y\n", "Daily/2026-09-25.md", in: brain)
        try write("{}", ".obsidian/workspace.json", in: brain)
        try write("# changed\n", "BRAIN.md", in: brain)
        #expect(try git.status(scope: Brain.ownEditsScope).sorted() == ["BRAIN.md", "memory/acme/new/deep.md"])
    }
}

/// The list each account keeps of what it wrote, until its next save.
@Suite struct TouchedLedgerTests {
    @Test func takeThenFinishKeepsWhatWasNotSaved() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/a.md")
        try ledger.append("memory/b.md")
        try ledger.append("memory/a.md")
        #expect(try ledger.take() == ["memory/a.md", "memory/b.md"])
        #expect(FileManager.default.fileExists(atPath: ledger.sending.path) && !FileManager.default.fileExists(atPath: ledger.file.path))
        // Written while the save runs: kept for the next one.
        try ledger.append("memory/c.md")
        #expect(TouchedLedger.claimed(in: brain) == ["memory/a.md", "memory/b.md", "memory/c.md"])
        try ledger.finish(keeping: ["memory/b.md"])
        #expect(!FileManager.default.fileExists(atPath: ledger.sending.path))
        #expect(try ledger.take() == ["memory/c.md", "memory/b.md"])
        try ledger.finish(keeping: [])
        #expect(TouchedLedger.claimed(in: brain).isEmpty)
    }

    /// A save stopped half way (the Mac slept, the process was killed) leaves its list aside: the next save takes it too.
    @Test func aListLeftAsideIsTakenAgain() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/a.md")
        _ = try ledger.take()
        try ledger.append("memory/b.md")
        #expect(try ledger.take() == ["memory/a.md", "memory/b.md"])
    }

    /// Hooks of several sessions write at the same time as saves take the list (one save at a time, under the memory's
    /// lock): no line is lost.
    @Test func concurrentWritersLoseNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        let git = BrainGit(brain: brain)
        let total = 200
        let taken = LockedPaths()
        DispatchQueue.concurrentPerform(iterations: total + 20) { index in
            if index < total { try? ledger.append("memory/n\(index).md") }
            else {
                try? git.withLock(timeout: 10) {
                    if let paths = try? ledger.take() { taken.add(paths); try? ledger.finish(keeping: []) }
                }
            }
        }
        taken.add(try ledger.take())
        #expect(taken.all.count == total)
    }

    final class LockedPaths: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String> = []
        func add(_ more: [String]) { lock.lock(); paths.formUnion(more); lock.unlock() }
        var all: Set<String> { lock.lock(); defer { lock.unlock() }; return paths }
    }
}

/// The person's own edits: saved as You, only once nothing moved for ten minutes and no Claude Code session runs.
@Suite struct OwnEditsTests {
    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func yourEditsAreSavedAsYouOnceQuiet() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write("# mine\n", "memory/acme/idea.md", in: brain)
        try write("# mine too\n", "memory/acme/plan.md", in: brain)
        try write("# claude\n", "memory/acme/claude.md", in: brain)
        try write("# today\n", "Daily/2026-09-25.md", in: brain)
        try write("{}", ".obsidian/workspace.json", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/claude.md")
        let edits = OwnEdits(brain: brain, git: git, held: HeldStore(paths: home.paths, memoryID: "shared"))
        let now = Date()

        #expect(try edits.save(now: now, sessionRunning: false) == .tooRecent)
        #expect(try edits.save(now: now.addingTimeInterval(3600), sessionRunning: true) == .sessionRunning)
        #expect(try git.log().isEmpty)

        let outcome = try edits.save(now: now.addingTimeInterval(OwnEdits.quietPeriod + 60), sessionRunning: false)
        let saved = try #require({ if case .saved(let paths) = outcome { return paths }; return nil }())
        #expect(!saved.contains("memory/acme/claude.md"), "what an account wrote waits for that account")
        #expect(!saved.contains { $0.hasPrefix("Daily/") || $0.hasPrefix(".obsidian/") })
        #expect(saved.contains("memory/acme/idea.md") && saved.contains("memory/acme/plan.md") && saved.contains("BRAIN.md"))
        let last = try #require(try git.log(limit: 1).first)
        #expect(last.authorName == "You" && last.authorEmail == "outside.claude@brainmerge.local")
        #expect(last.authorEmail == OwnEdits.author.email)
        #expect(last.message == MemorySentence.message(name: "You", files: last.files, byYou: true))
        #expect(try edits.save(now: now.addingTimeInterval(7200), sessionRunning: false) == .nothing)
    }

    /// A deletion counts from when its folder last changed.
    @Test func aDeletionIsDatedByItsFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        try write("# old\n", "memory/acme/old.md", in: brain)
        try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Start")
        try FileManager.default.removeItem(at: brain.root.appending(path: "memory/acme/old.md"))
        let edits = OwnEdits(brain: brain, git: git, held: HeldStore(paths: home.paths, memoryID: "shared"))
        #expect(edits.newestChange(of: ["memory/acme/old.md"]).map { abs($0.timeIntervalSinceNow) < 60 } == true)
        let gone = brain.root.appending(path: "memory/acme")
        try FileManager.default.removeItem(at: gone)
        #expect(edits.newestChange(of: ["memory/acme/old.md"]).map { abs($0.timeIntervalSinceNow) < 60 } == true)
        #expect(try edits.save(now: Date().addingTimeInterval(OwnEdits.quietPeriod + 60), sessionRunning: false) == .saved(["memory/acme/old.md"]))
    }
}

/// True the first time it is asked only.
final class FirstTime: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = false
    func now() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { asked = true }
        return !asked
    }
}
