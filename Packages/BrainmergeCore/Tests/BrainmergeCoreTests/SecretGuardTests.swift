import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Key-shaped values, assembled when the tests run: the repository itself never holds one (GitHub's push protection would
/// block it, and it would be a key in the history, the very thing the guard prevents).
enum SecretFixtures {
    /// Deterministic characters that look random: mixed case, digits.
    static func noise(_ count: Int, _ alphabet: String = "aB3dE5fG7hJ9kL2mN4pQ6rS8tU1vW0xYz", step: Int = 7) -> String {
        let chars = Array(alphabet)
        return String((0..<count).map { chars[($0 * step + 3) % chars.count] })
    }

    static var gitHub: String { "gh" + "p_" + noise(36) }
    static var gitHubFineGrained: String { "github" + "_pat_" + noise(22) + "_" + noise(59, step: 5) }
    static var anthropic: String { "sk-" + "ant-" + "api03-" + noise(48) }
    static var openAI: String { "sk-" + "proj-" + noise(48) }
    static var gitLab: String { "gl" + "pat-" + noise(20) }
    static var slack: String { "xo" + "xb-" + "1234567890" + "-" + noise(24) }
    static var aws: String { "AK" + "IA" + noise(16, "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567") }
    static var google: String { "AI" + "za" + noise(35) }
    static var stripe: String { "sk" + "_live_" + noise(24) }
    static var npm: String { "np" + "m_" + noise(36) }
    static var pem: String { "-----BEGIN " + "RSA PRIVATE" + " KEY-----" }
    static var password: String { noise(24, step: 13) }
}

@Suite struct SecretShapesTests {
    @Test func eachShapeIsRecognizedInALine() {
        let f = SecretFixtures.self
        let cases: [(String, SecretShape)] = [
            ("deploy with token \(f.gitHub) then push", .gitHub),
            ("GH_TOKEN=\(f.gitHubFineGrained)", .gitHub),
            ("export ANTHROPIC_API_KEY=\(f.anthropic)", .anthropic),
            ("OPENAI_API_KEY: \(f.openAI)", .openAI),
            ("gitlab: \(f.gitLab)", .gitLab),
            ("slack bot \(f.slack)", .slack),
            ("aws_access_key_id = \(f.aws)", .aws),
            ("maps key \(f.google)", .google),
            ("stripe \(f.stripe)", .stripe),
            ("//registry.npmjs.org/:_authToken=\(f.npm)", .npm),
            (f.pem, .privateKey),
            ("DB_PASSWORD=\(f.password)", .assignment),
            ("secret: \"\(f.password)\"", .assignment),
        ]
        for (line, shape) in cases {
            #expect(SecretShapes.match(line) == shape, "\(shape)")
        }
    }

    /// Everyday notes are not keys: prose, slugs, hashes named as such, placeholders, low-entropy values, links.
    @Test func everydayNotesAreNotKeys() {
        for line in ["The password policy: at least twelve characters, rotated every quarter.",
                     "- task-management-system-overview-and-roadmap-2026 is the project slug",
                     "Deploy: git push origin main, then check the desk-reservation-service logs",
                     "token: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                     "api_key: ${ANTHROPIC_API_KEY_FROM_THE_ENVIRONMENT}",
                     "password: <put-your-own-password-here-please>",
                     "token_url: https://example.com/oauth2/token/endpoint/v2",
                     "commit 3f9a1c2e8b7d6f5a4c3b2a1908f7e6d5c4b3a291 fixed it",
                     "secret: short"] {
            #expect(SecretShapes.match(line) == nil, "\(line)")
        }
    }

    @Test func shapesSayWhatTheyLookLike() {
        #expect(SecretShape.gitHub.label == "a GitHub token")
        #expect(SecretShape.privateKey.label == "a private key")
        #expect(SecretShape.assignment.label == "a password or key")
        #expect(SecretShape.allCases.allSatisfy { !$0.label.isEmpty })
    }
}

@Suite struct SecretGuardTests {
    func diff(_ path: String, start: Int, _ added: [String]) -> String {
        """
        diff --git a/\(path) b/\(path)
        index 0000000..1111111 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -0,0 +\(start),\(added.count) @@
        \(added.map { "+" + $0 }.joined(separator: "\n"))

        """
    }

    @Test func addedLinesAreScannedWithTheirNumbers() {
        let text = diff("memory/acme/deploy.md", start: 10, ["# Deploy", "", "token \(SecretFixtures.gitHub)"])
            + diff("memory/acme/notes.md", start: 1, ["nothing here"])
        let found = SecretGuard.scan(diff: text) { _, _ in false }
        #expect(found.count == 1)
        #expect(found.first?.path == "memory/acme/deploy.md" && found.first?.line == 12 && found.first?.shape == .gitHub)
        #expect(found.first?.hash == LineHash(line: "token \(SecretFixtures.gitHub)"))
        let allowed = SecretGuard.scan(diff: text) { path, hash in path == "memory/acme/deploy.md" && hash == found.first?.hash }
        #expect(allowed.isEmpty)
    }

    /// A name git quotes (a quote, a tab, a non-ASCII letter when quotePath is on) is read back as written.
    @Test func quotedNamesAreReadBack() {
        let text = """
        diff --git "a/memory/acme/d\\303\\251ploy \\"v2\\".md" "b/memory/acme/d\\303\\251ploy \\"v2\\".md"
        --- /dev/null
        +++ "b/memory/acme/d\\303\\251ploy \\"v2\\".md"
        @@ -0,0 +1 @@
        +\(SecretFixtures.pem)

        """
        #expect(SecretGuard.scan(diff: text) { _, _ in false }.first?.path == "memory/acme/déploy \"v2\".md")
    }

    /// Git ends the `+++` line with a tab when a name holds a space, after a closing quote too: the tab is not part of it.
    @Test func theTabAfterANameIsNotPartOfIt() {
        let text = """
        diff --git a/memory/acme/deploy notes.md b/memory/acme/deploy notes.md
        --- /dev/null
        +++ b/memory/acme/deploy notes.md\t
        @@ -0,0 +1 @@
        +\(SecretFixtures.pem)
        diff --git "a/memory/acme/deploy \\"v2\\" notes.md" "b/memory/acme/deploy \\"v2\\" notes.md"
        --- /dev/null
        +++ "b/memory/acme/deploy \\"v2\\" notes.md"\t
        @@ -0,0 +1 @@
        +\(SecretFixtures.pem)

        """
        #expect(SecretGuard.scan(diff: text) { _, _ in false }.map(\.path)
                == ["memory/acme/deploy notes.md", "memory/acme/deploy \"v2\" notes.md"])
    }

    /// What the guard keeps can never carry the value: a path, a number, a shape and a digest, no text of the line.
    @Test func resultsHoldNoTextOfTheLine() throws {
        let note = HeldNote(account: "work", path: "memory/acme/deploy.md", line: 3, shape: .gitHub, hash: LineHash(line: "x"))
        func strings(_ value: Any) -> [String] {
            Mirror(reflecting: value).children.compactMap { child in child.value is String ? child.label : nil }
        }
        #expect(Set(strings(note)).isSubset(of: ["account", "path"]), "\(strings(note))")
        #expect(strings(SecretGuard.Finding(path: "p", line: 1, shape: .aws, hash: LineHash(line: "x"))) == ["path"])
        #expect(strings(LineHash(line: "x")) == ["hex"])
        #expect(LineHash(line: "x").hex.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)

        let value = SecretFixtures.anthropic
        let found = SecretGuard.scan(diff: diff("memory/a.md", start: 1, ["key \(value)"])) { _, _ in false }
        let encoded = String(decoding: try JSONEncoder().encode(found), as: UTF8.self) + String(describing: found)
        #expect(!found.isEmpty)
        #expect(!encoded.contains(value) && !encoded.contains(String(value.suffix(12))))
    }
}

/// The guard inside a save: a file that looks like it holds a key is left out of the commit and kept on the account's
/// list; its neighbors are saved. What is kept about it is its path, line, shape and digest, never the line.
@Suite struct GuardedSaveTests {
    let work = Identity(slug: "work", name: "Work", tint: .blue)

    func write(_ text: String, _ path: String, in brain: Brain) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The index, with names as written (NUL separated, never quoted).
    func tracked(_ git: BrainGit) throws -> [String] {
        try Shell().check("/usr/bin/git", ["ls-files", "-z"], cwd: git.brain.root).split(separator: "\0").map(String.init)
    }

    /// Real git, with `after` run once the save has read what it adds (`git diff --cached`), and that output passed
    /// through `rewrite`.
    func watchedGit(_ brain: Brain, rewrite: @escaping @Sendable (String) -> String = { $0 },
             after: @escaping @Sendable () throws -> Void = {}) -> BrainGit {
        BrainGit(brain: brain, shell: Shell { executable, arguments, cwd, environment in
            let result = try Shell().run(executable, arguments, cwd: cwd, environment: environment)
            guard arguments.contains("diff"), arguments.contains("--cached") else { return result }
            try after()
            return ShellResult(status: result.status, stdout: rewrite(result.stdout), stderr: result.stderr)
        })
    }

    func setup(_ home: TempHome) throws -> (Brain, BrainGit, HeldStore) {
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        return (brain, BrainGit(brain: brain), HeldStore(paths: home.paths, memoryID: "shared"))
    }

    @Test func aHeldFileIsNotCommittedWhileItsNeighborsAre() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        let value = SecretFixtures.gitHub
        try write("# Deploy\n\nUse \(value) to push.\n", "memory/acme-api/deploy.md", in: brain)
        try write("# Prices\n", "memory/acme-api/prices.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/acme-api/deploy.md")
        try ledger.append("memory/acme-api/prices.md")

        let outcome = try AccountSave(brain: brain, git: git, held: held).run(for: work)
        #expect(outcome.saved == ["memory/acme-api/prices.md"])
        #expect(outcome.held.map(\.path) == ["memory/acme-api/deploy.md"])
        #expect(try tracked(git) == ["memory/acme-api/prices.md"])
        let staged = try git.shell.check("/usr/bin/git", ["diff", "--cached", "--name-only"], cwd: brain.root)
        #expect(staged.isEmpty, "the held file is unstaged, the index only")
        #expect(held.load().held == [HeldNote(account: "work", path: "memory/acme-api/deploy.md", line: 3, shape: .gitHub,
                                              hash: LineHash(line: "Use \(value) to push."))])
        #expect(TouchedLedger.claimed(in: brain) == ["memory/acme-api/deploy.md"], "it waits on the account's list")
        let file = try String(contentsOf: held.file, encoding: .utf8)
        #expect(!file.contains(value) && !file.contains("Use "))

        // Held again at the next save, still once.
        _ = try AccountSave(brain: brain, git: git, held: held).run(for: work)
        #expect(held.load().held.count == 1)
    }

    /// A held note never reaches the memory's git, not even as an object no commit points to: a copy or a backup of the
    /// folder never carries the key. The first save of a memory and a later one alike.
    @Test func aHeldNoteIsNeverWrittenIntoTheMemorysGit() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        let first = SecretFixtures.gitHub, second = SecretFixtures.npm
        for (value, prices) in [(first, "# Prices\n"), (second, "# Prices\n\n10 a day\n")] {
            try write("# Deploy\n\nUse \(value) to push.\n", "memory/acme/deploy.md", in: brain)
            try write(prices, "memory/acme/prices.md", in: brain)
            try ledger.append("memory/acme/deploy.md")
            try ledger.append("memory/acme/prices.md")
            let outcome = try AccountSave(brain: brain, git: git, held: held).run(for: work)
            #expect(outcome.saved == ["memory/acme/prices.md"])
            #expect(outcome.held.map(\.path) == ["memory/acme/deploy.md"])
        }
        let objects = try Shell().check("/usr/bin/git", ["cat-file", "--batch-all-objects", "--batch"], cwd: brain.root)
        #expect(objects.contains("10 a day"), "the saved notes are there")
        #expect(!objects.contains(first) && !objects.contains(second) && !objects.contains("Use "))
    }

    /// "It's not a secret": the digest goes to the memory's own list, and the next save commits the file. Lines already
    /// saved are not scanned again when the note changes.
    @Test func anAllowedLineIsSavedAndContextLinesAreNotRescanned() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        try write("# Deploy\nUse \(SecretFixtures.gitHub) to push.\n", "memory/acme/deploy.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/acme/deploy.md")
        let first = try AccountSave(brain: brain, git: git, held: held).run(for: work)
        let note = try #require(first.held.first)

        try HeldDecision.notASecret(note, brain: brain, store: held)
        #expect(held.load().held.isEmpty)
        #expect(NotSecrets.hashes(in: brain) == [note.hash.hex])
        #expect(try AccountSave(brain: brain, git: git, held: held).run(for: work).saved == ["memory/acme/deploy.md"])

        try write("# Deploy\nUse \(SecretFixtures.gitHub) to push.\nThen tag it.\n", "memory/acme/deploy.md", in: brain)
        // Even with the line no longer allowed, only the added line is read.
        try FileManager.default.removeItem(at: brain.notSecretsFile)
        try ledger.append("memory/acme/deploy.md")
        #expect(try AccountSave(brain: brain, git: git, held: held).run(for: work).saved == ["memory/acme/deploy.md"])
    }

    /// "Save anyway": once, for the next save of the account that wrote it.
    @Test func saveAnywayAllowsTheNextSaveOnly() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        try write("key \(SecretFixtures.aws)\n", "memory/acme/aws.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/acme/aws.md")
        let note = try #require(try AccountSave(brain: brain, git: git, held: held).run(for: work).held.first)
        try HeldDecision.saveAnyway(note, store: held)
        #expect(held.load().held.isEmpty && held.load().allowed.count == 1)
        #expect(try AccountSave(brain: brain, git: git, held: held).run(for: work).saved == ["memory/acme/aws.md"])
        #expect(held.load().allowed.isEmpty, "used once")

        try write("key \(SecretFixtures.aws)\nkey \(SecretFixtures.aws)\n", "memory/acme/aws.md", in: brain)
        try ledger.append("memory/acme/aws.md")
        #expect(try AccountSave(brain: brain, git: git, held: held).run(for: work).held.count == 1)
        #expect(NotSecrets.hashes(in: brain).isEmpty, "Save anyway never marks the line as safe for good")
    }

    /// The person's own edits go through the same guard.
    @Test func yourOwnEditsAreGuardedToo() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        try write("DB_PASSWORD=\(SecretFixtures.password)\n", "memory/acme/db.md", in: brain)
        try write("# Idea\n", "memory/acme/idea.md", in: brain)
        let outcome = try OwnEdits(brain: brain, git: git, held: held).save(now: Date().addingTimeInterval(3600), sessionRunning: false)
        guard case .saved(let saved) = outcome else { Issue.record("\(outcome)"); return }
        #expect(saved.contains("memory/acme/idea.md") && !saved.contains("memory/acme/db.md"))
        #expect(held.load().held.map(\.account) == [nil])
        #expect(held.load().held.first?.shape == .assignment)
    }

    /// A name with a space, or one git quotes, is held like any other and waits under its own name: git's headers end
    /// such a name with a tab, which is not part of it.
    @Test(arguments: ["memory/acme/deploy notes.md", "memory/acme/deploy \"v2\" notes.md", "memory/acme/déploy\tv2.md"])
    func aNameWithASpaceOrQuotesIsHeld(_ name: String) throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        try write("# Deploy\nUse \(SecretFixtures.gitHub) to push.\n", name, in: brain)
        try write("# Prices\n", "memory/acme/prices.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append(name)
        try ledger.append("memory/acme/prices.md")

        let outcome = try AccountSave(brain: brain, git: git, held: held).run(for: work)
        #expect(outcome.saved == ["memory/acme/prices.md"])
        #expect(outcome.held.map(\.path) == [name])
        #expect(held.load().held.map(\.path) == [name])
        #expect(try tracked(git) == ["memory/acme/prices.md"], "the note is neither saved nor tracked")
        #expect(TouchedLedger.claimed(in: brain) == [name])
    }

    /// Should the guard name a file the save did not stage, it cannot tell which note holds the key: nothing is saved,
    /// and every path waits on the account's list.
    @Test func aFindingThatNamesNoStagedFileSavesNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _, held) = try setup(home)
        let git = watchedGit(brain, rewrite: {
            $0.replacingOccurrences(of: "+++ b/memory/acme/deploy.md", with: "+++ b/memory/acme/elsewhere.md")
        })
        try write("Use \(SecretFixtures.gitHub) to push.\n", "memory/acme/deploy.md", in: brain)
        try write("# Prices\n", "memory/acme/prices.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        try ledger.append("memory/acme/deploy.md")
        try ledger.append("memory/acme/prices.md")

        #expect(throws: BrainmergeError.heldFileUnknown) { try AccountSave(brain: brain, git: git, held: held).run(for: work) }
        #expect(try tracked(git).isEmpty)
        #expect(TouchedLedger.claimed(in: brain) == ["memory/acme/deploy.md", "memory/acme/prices.md"])
        #expect(held.load().held.isEmpty)
    }

    /// The commit holds exactly what the guard read: a note rewritten between the two keeps its new text for the next
    /// save, unstaged.
    @Test func theCommitHoldsWhatWasRead() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, _, held) = try setup(home)
        let note = brain.root.appending(path: "memory/acme/deploy.md")
        let late = "# Deploy\nUse \(SecretFixtures.gitHub) to push.\n"
        let git = watchedGit(brain, after: { try Data(late.utf8).write(to: note) })
        try write("# Deploy\n", "memory/acme/deploy.md", in: brain)
        try TouchedLedger(brain: brain, slug: "work").append("memory/acme/deploy.md")

        #expect(try AccountSave(brain: brain, git: git, held: held).run(for: work).saved == ["memory/acme/deploy.md"])
        let committed = try Shell().check("/usr/bin/git", ["show", "HEAD:memory/acme/deploy.md"], cwd: brain.root)
        #expect(committed == "# Deploy\n")
        #expect(try String(contentsOf: note, encoding: .utf8) == late)
        let status = try Shell().check("/usr/bin/git", ["status", "--porcelain", "--", "memory/acme/deploy.md"], cwd: brain.root)
        #expect(status == " M memory/acme/deploy.md\n", "the new text waits, unstaged")
    }

    /// A note git would call binary is still read: a `-diff` attribute or a NUL byte never hides its lines.
    @Test func aNoteGitCallsBinaryIsStillRead() throws {
        let home = try TempHome(); defer { home.remove() }
        let (brain, git, held) = try setup(home)
        try write("* -diff\n", "memory/acme/.gitattributes", in: brain)
        try write("Use \(SecretFixtures.gitHub) to push.\n", "memory/acme/deploy.md", in: brain)
        try write("a\u{0}b\nkey \(SecretFixtures.aws)\n", "memory/kayak/raw.md", in: brain)
        let ledger = TouchedLedger(brain: brain, slug: "work")
        for path in ["memory/acme/.gitattributes", "memory/acme/deploy.md", "memory/kayak/raw.md"] { try ledger.append(path) }

        let outcome = try AccountSave(brain: brain, git: git, held: held).run(for: work)
        #expect(outcome.saved == ["memory/acme/.gitattributes"])
        #expect(Set(outcome.held.map(\.path)) == ["memory/acme/deploy.md", "memory/kayak/raw.md"])
        #expect(try tracked(git) == ["memory/acme/.gitattributes"])
    }
}
