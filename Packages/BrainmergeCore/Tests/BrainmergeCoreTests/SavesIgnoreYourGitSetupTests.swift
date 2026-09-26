import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// A save is Brainmerge's own commit: the person's git setup never takes part in it. No global or system config (signing,
/// a hook folder), no hook or signing the memory's own config asks for, none of the GIT_ variables a session may carry,
/// and a git that hangs is stopped.
@Suite struct SavesIgnoreYourGitSetupTests {
    let work = Identity(slug: "work", name: "Work", tint: .blue)

    func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    @Test func aSaveTakesNothingFromYourGitSetup() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        // The person's setup: every hook refuses, signing fails, and the global config asks for both.
        let person = home.url.appending(path: "person")
        let hooks = person.appending(path: "hooks")
        for hook in ["pre-commit", "commit-msg", "post-commit", "reference-transaction", "post-index-change"] {
            try write("#!/bin/sh\nexit 1\n", to: hooks.appending(path: hook), executable: true)
        }
        let config = "[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /usr/bin/false\n[core]\n\thooksPath = \(hooks.path)\n"
        try write(config, to: person.appending(path: ".gitconfig"))
        try write(config, to: person.appending(path: "system-gitconfig"))
        // The memory's own config asks for them too.
        for (key, value) in [("commit.gpgsign", "true"), ("gpg.program", "/usr/bin/false"), ("core.hooksPath", hooks.path)] {
            try Shell().check("/usr/bin/git", ["config", key, value], cwd: brain.root)
        }
        // What a session may carry: the person's name, another repository's index, config of its own.
        let otherIndex = person.appending(path: "other-index")
        var session = ProcessInfo.processInfo.environment
        session["HOME"] = person.path
        session["GIT_CONFIG_SYSTEM"] = person.appending(path: "system-gitconfig").path
        session["GIT_CONFIG_PARAMETERS"] = "'commit.gpgsign'='true'"
        session["GIT_AUTHOR_NAME"] = "Person Env"; session["GIT_AUTHOR_EMAIL"] = "person@example.com"
        session["GIT_COMMITTER_NAME"] = "Person Env"; session["GIT_COMMITTER_EMAIL"] = "person@example.com"
        session["GIT_INDEX_FILE"] = otherIndex.path
        let git = BrainGit(brain: brain, shell: Shell(inheriting: session))
        try write("# note\n", to: brain.root.appending(path: "memory/acme/note.md"))
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/note.md")

        let outcome = try AccountSave(brain: brain, git: git, held: HeldStore(paths: home.paths, memoryID: "shared")).run(for: work)
        #expect(outcome.saved == ["memory/acme/note.md"])
        let signed = try Shell().check("/usr/bin/git", ["log", "-1", "--format=%an <%ae> %cn <%ce>"], cwd: brain.root)
        #expect(signed == "Work <\(work.gitAuthor.email)> Work <\(work.gitAuthor.email)>\n")
        #expect(!FileManager.default.fileExists(atPath: otherIndex.path), "another repository's index is never touched")
    }

    /// A git that hangs (a program it waits on, a file that never comes) is stopped: a hook never waits on it for ever.
    @Test(.timeLimit(.minutes(1))) func aGitThatHangsIsStopped() throws {
        let started = Date()
        #expect(throws: BrainmergeError.timedOut(command: "/usr/bin/git -c alias.pause=!sleep 20 pause")) {
            try Shell(inheriting: nil, gitTimeout: 1).run("/usr/bin/git", ["-c", "alias.pause=!sleep 20", "pause"])
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
