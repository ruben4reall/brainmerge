import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite(.serialized) struct CLISmokeTests {
    func run(_ e: ManagerEnv, _ arguments: [String], extra: [String: String] = [:]) throws -> ShellResult {
        var env = ["BRAINMERGE_HOME": e.home.url.path, "BRAINMERGE_CLAUDE_APP": e.claude.url.path]
        env.merge(extra) { $1 }
        return try Shell().run(Products.brainmerge.path, arguments, environment: env)
    }

    @Test func brainInitUsesTheSavedLanguageByDefault() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        var state = try e.store.load(); state.brainLanguage = .fr; try e.store.save(state)
        let result = try run(e, ["brain", "init"])
        #expect(result.status == 0)
        #expect(try String(contentsOf: e.home.paths.defaultBrain.appending(path: "BRAIN.md"), encoding: .utf8).hasPrefix("# Cerveau partagé"))
    }

    /// Doctor's advice for a memory whose folder is gone is a command that works as printed, pasted in a shell: the
    /// memory is still used by an account, and its name and folder hold spaces.
    @Test func doctorsAdviceForAMissingMemoryWorksAsPrinted() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Me")
        let folder = e.home.url.appending(path: "Client Work", directoryHint: .isDirectory)
        #expect(try run(e, ["brain", "add", "--name", "Client Work", folder.path]).status == 0)
        #expect(try run(e, ["identity", "add", "--name", "Work", "--brain", "client-work"]).status == 0)
        try FileManager.default.removeItem(at: folder)

        let doctor = try run(e, ["doctor"])
        let line = try #require(doctor.stdout.split(separator: "\n").first { $0.contains("Memory: Client Work") })
        let command = try #require(line.range(of: "Run: ").map { String(line[$0.upperBound...]) })
        #expect(command == "brainmerge brain relocate client-work '\(folder.path)'", "\(line)")
        let relocated = try run(e, ["brain", "relocate", "client-work", folder.path])
        #expect(relocated.status == 0, "\(relocated.stderr)")
        let again = try run(e, ["doctor"])
        #expect(again.stdout.split(separator: "\n").contains { $0.contains("Memory: Client Work") && $0.contains("git ready") }, "\(again.stdout)")
    }

    /// `brain init` never moves a default memory that is in place: a plain one keeps it where it is, and another folder is
    /// refused with what to do, before anything changes, so the projects' links, Claude's instructions and the saves stay
    /// with the memory the notes are in. Once its folder is gone, init points it at another folder and the links follow.
    @Test func brainInitNeverMovesTheDefaultMemory() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        let notes = e.home.url.appending(path: "My Notes").path
        #expect(try run(e, ["brain", "init", notes]).status == 0)
        #expect(try run(e, ["adopt-primary", "--name", "Me"]).status == 0)
        let claudeMD = try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == Brain(root: URL(fileURLWithPath: notes)).memoryDir(forProject: "atelier").path)

        let plain = try run(e, ["brain", "init"])
        #expect(plain.status == 0, "\(plain.stderr)")
        #expect(try e.store.load().brainPath == notes)
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.defaultBrain.path))

        let other = e.home.url.appending(path: "Brain2").path
        let moved = try run(e, ["brain", "init", other])
        #expect(moved.status != 0)
        #expect(moved.stderr.contains(notes), "\(moved.stderr)")
        #expect(try e.store.load().brainPath == notes)
        #expect(!FileManager.default.fileExists(atPath: other))
        #expect(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8) == claudeMD)

        try FileManager.default.removeItem(atPath: notes)
        #expect(try run(e, ["brain", "init", other]).status == 0)
        #expect(try e.store.load().brainPath == other)
        #expect(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8).contains(other))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == Brain(root: URL(fileURLWithPath: other)).memoryDir(forProject: "atelier").path)
    }

    @Test func fullScenarioThroughTheCLI() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }

        let doctor0 = try run(e, ["doctor", "--json"])
        #expect(doctor0.status == 0)
        #expect((try JSONSerialization.jsonObject(with: Data(doctor0.stdout.utf8)) as? [[String: Any]])?.isEmpty == false)

        let brainPath = e.home.url.appending(path: "Brain").path
        #expect(try run(e, ["brain", "init", brainPath, "--lang", "fr"]).status == 0)
        #expect(try String(contentsOf: e.brain.brainMD, encoding: .utf8).hasPrefix("# Cerveau partagé"))
        #expect(try e.store.load().brainPath == brainPath)

        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        #expect(try e.store.load().primary?.slug == "perso")
        #expect(FileManager.default.fileExists(atPath: e.home.url.appending(path: ".local/bin/brainmerge").path))

        let add = try run(e, ["identity", "add", "--name", "Client", "--tint", "blue"])
        #expect(add.status == 0, "\(add.stderr)")
        #expect(FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))

        let list = try run(e, ["identity", "list", "--json"])
        #expect(list.stdout.contains("\"slug\" : \"client\""))

        let dir = e.brain.memoryDir(forProject: "atelier")
        try Data("# souvenir\n".utf8).write(to: dir.appending(path: "MEMORY.md"))
        #expect(try run(e, ["touched", "--identity", "client"], input: edit(dir.appending(path: "MEMORY.md").path)).status == 0)
        let sync = try run(e, ["sync", "--identity", "client"])
        #expect(sync.status == 0)
        let log = try BrainGit(brain: e.brain).log(limit: 1)
        #expect(log.first?.authorName == "Client")
        #expect(log.first?.authorEmail == "client@brainmerge.local")
        #expect(log.first?.message == "Client updated its notes about atelier")
        #expect(try run(e, ["brain", "timeline"]).stdout.contains("Client"))
        #expect(try run(e, ["brain", "status"]).stdout.contains("atelier"))

        #expect(try run(e, ["identity", "edit", "client", "--name", "ClientStudio", "--tint", "green"]).status == 0)
        #expect(FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "ClientStudio").path))
        #expect(try run(e, ["identity", "remove", "client"]).status == 0)
        #expect(try e.store.load().identity(slug: "client") == nil)
        #expect(FileManager.default.fileExists(atPath: e.home.paths.cliProfile(slug: "client", isPrimary: false).path))
        #expect(try run(e, ["identity", "launch", "nope"]).status != 0)
    }

    @Test func syncNeverBlocksClaude() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let logFile = e.home.paths.logsDir.appending(path: "sync.log")

        #expect(try run(e, ["sync", "--identity", "nope"]).status == 0)
        #expect(try String(contentsOf: logFile, encoding: .utf8).contains("nope: unknown identity"))

        let git = BrainGit(brain: e.brain)
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { try? git.withLock(timeout: 5) { acquired.signal(); release.wait() } }
        acquired.wait()
        let start = Date()
        let locked = try run(e, ["sync", "--identity", "perso"], extra: ["BRAINMERGE_LOCK_TIMEOUT": "1"])
        release.signal()
        #expect(locked.status == 0)
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(try String(contentsOf: logFile, encoding: .utf8).contains("lock"))

        try FileManager.default.removeItem(at: e.brain.root)
        let missing = try run(e, ["sync", "--identity", "perso"])
        #expect(missing.status == 0)
        #expect(try String(contentsOf: logFile, encoding: .utf8).contains("memory missing"))
    }

    /// Each save leaves how it went for the app, per account: committed, nothing, or failed with the reason's code.
    @Test func syncWritesHowTheSaveWent() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let statuses = SaveStatusStore(paths: e.home.paths)
        let start = Date().addingTimeInterval(-1)

        // Its lists of projects and accounts, written when it was set up.
        #expect(try run(e, ["sync", "--identity", "perso"]).status == 0)
        let committed = try #require(statuses.read(slug: "perso"))
        #expect(committed.outcome == .committed && committed.reason == nil && committed.date >= start)
        #expect(try run(e, ["sync", "--identity", "perso"]).status == 0)
        #expect(statuses.read(slug: "perso")?.outcome == .nothing)

        #expect(try run(e, ["sync", "--identity", "nope"]).status == 0)
        #expect(statuses.read(slug: "nope") == SaveStatus(date: try #require(statuses.read(slug: "nope")?.date), outcome: .failed, reason: .unknown))

        let git = BrainGit(brain: e.brain)
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { try? git.withLock(timeout: 5) { acquired.signal(); release.wait() } }
        acquired.wait()
        let locked = try run(e, ["sync", "--identity", "perso"], extra: ["BRAINMERGE_LOCK_TIMEOUT": "1"])
        release.signal()
        #expect(locked.status == 0)
        #expect(statuses.read(slug: "perso")?.outcome == .failed)
        #expect(statuses.read(slug: "perso")?.reason == .locked)

        try FileManager.default.removeItem(at: e.brain.root)
        #expect(try run(e, ["sync", "--identity", "perso"]).status == 0)
        #expect(statuses.read(slug: "perso")?.outcome == .failed)
        #expect(statuses.read(slug: "perso")?.reason == .notARepository)
    }

    /// `brain wire` (and `brain init`) repair every account they can: one whose Claude Code folder is gone is named and
    /// skipped, never a stop for the accounts after it. The command still fails, so the missing folder is not missed.
    @Test func brainWireRepairsEveryAccountItCan() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(try run(e, ["identity", "add", "--name", "Work", "--no-desktop"]).status == 0)
        #expect(try run(e, ["identity", "add", "--name", "Client", "--no-desktop"]).status == 0)
        let work = e.home.paths.cliProfile(slug: "work", isPrimary: false)
        let client = CLIProfile(directory: e.home.paths.cliProfile(slug: "client", isPrimary: false))
        try FileManager.default.removeItem(at: work)
        for command in [["brain", "wire"], ["brain", "init"]] {
            try Data("{}".utf8).write(to: e.primaryProfile.settingsFile)
            try Data("{}".utf8).write(to: client.settingsFile)
            let result = try run(e, command)
            #expect(result.status != 0, "\(command)")
            #expect(result.stderr.contains(work.path), "\(command): \(result.stderr)")
            #expect(HookInstaller.health(settingsFile: e.primaryProfile.settingsFile, cliPath: e.cliPath, slug: "perso") == .current, "\(command)")
            #expect(HookInstaller.health(settingsFile: client.settingsFile, cliPath: e.cliPath, slug: "client") == .current, "\(command)")
        }
        #expect(!FileManager.default.fileExists(atPath: work.path), "a missing folder is never recreated")
    }

    /// Like Claude Code runs a hook: the session's JSON on the standard input, which is then closed.
    /// `without`: variables the run must not inherit from the test's own environment.
    func run(_ e: ManagerEnv, _ arguments: [String], input: String, without: Set<String> = []) throws -> ShellResult {
        let process = Process()
        process.executableURL = Products.brainmerge
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["BRAINMERGE_HOME": e.home.url.path, "BRAINMERGE_CLAUDE_APP": e.claude.url.path]) { $1 }.filter { !without.contains($0.key) }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, stdout: String(decoding: out, as: UTF8.self), stderr: String(decoding: err, as: UTF8.self))
    }

    /// The SessionStart hook: what it prints would go into the session, so it prints nothing, and it never fails a session
    /// start, whatever it is given.
    @Test func wireHookPrintsNothingAndAlwaysExitsZero() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let logFile = e.home.paths.logsDir.appending(path: "sync.log")
        let kayak = e.home.url.path + "/kayak"
        func session(_ cwd: String) -> String {
            #"{"session_id":"sentinel-session","transcript_path":"/tmp/sentinel.jsonl","cwd":"\#(cwd)","hook_event_name":"SessionStart","source":"startup","model":"sentinel-model"}"#
        }
        let linked = try run(e, ["wire", "--identity", "perso", "--hook"], input: session(kayak))
        #expect(linked.status == 0 && linked.stdout.isEmpty && linked.stderr.isEmpty, "\(linked.stderr)")
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: kayak)).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "kayak").path)
        #expect(try String(contentsOf: logFile, encoding: .utf8).contains("perso: linked kayak"))

        let again = try run(e, ["wire", "--identity", "perso", "--hook"], input: session(kayak))
        #expect(again.status == 0 && again.stdout.isEmpty)
        for (arguments, input) in [(["wire", "--identity", "nope", "--hook"], session(kayak)),
                                   (["wire", "--identity", "perso", "--hook"], "{oops"),
                                   (["wire", "--identity", "perso", "--hook"], ""),
                                   (["wire", "--identity", "perso", "--hook"], #"{"cwd":42}"#),
                                   (["wire", "--identity", "perso", "--hook"], #"{"source":"startup"}"#)] {
            let result = try run(e, arguments, input: input)
            #expect(result.status == 0 && result.stdout.isEmpty, "\(arguments) \(input): \(result.stdout) \(result.stderr)")
        }
        let log = try String(contentsOf: logFile, encoding: .utf8)
        #expect(log.contains("nope"))
        #expect(!log.contains("sentinel"), "only the folder is read from the session")

        try FileManager.default.removeItem(at: e.brain.root)
        let missing = try run(e, ["wire", "--identity", "perso", "--hook"], input: session(e.home.url.path + "/other"))
        #expect(missing.status == 0 && missing.stdout.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: e.brain.root.path))
        #expect(!FileManager.default.fileExists(atPath: e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.home.url.path + "/other")).path))
    }

    /// The SessionStart hook's own bound on the memory's lock, with nothing overriding it: a save holding the lock never
    /// keeps a session start near Claude Code's 5 seconds for the hook. The project is linked at the next session start.
    @Test func wireHookGivesUpOnAHeldLockWellWithinItsTime() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let git = BrainGit(brain: e.brain)
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { try? git.withLock(timeout: 5) { acquired.signal(); release.wait() } }
        acquired.wait()
        let start = Date()
        let result = try run(e, ["wire", "--identity", "perso", "--hook"], input: #"{"cwd":"\#(e.home.url.path)/kayak"}"#,
                             without: ["BRAINMERGE_LOCK_TIMEOUT"])
        let elapsed = Date().timeIntervalSince(start)
        release.signal()
        #expect(result.status == 0 && result.stdout.isEmpty && result.stderr.isEmpty, "\(result.stderr)")
        #expect(elapsed < 4, "\(elapsed) s")
        let log = try String(contentsOf: e.home.paths.logsDir.appending(path: "sync.log"), encoding: .utf8)
        #expect(log.contains("perso: memory lock held by another process, link skipped"), "\(log)")
    }

    /// What Claude Code sends after an edit tool wrote a file.
    func edit(_ path: String, tool: String = "Write") -> String {
        #"{"session_id":"sentinel-session","transcript_path":"/tmp/sentinel.jsonl","cwd":"/tmp","hook_event_name":"PostToolUse","tool_name":"\#(tool)","tool_input":{"file_path":"\#(path)","content":"sentinel-content"},"tool_response":{"success":true}}"#
    }

    /// The PostToolUse hook notes what the account wrote, through its link, and prints nothing; the Stop hook then commits
    /// exactly that, under the account's name, with the words the Memory screen uses. Another account's note waits.
    @Test func eachAccountSavesExactlyWhatItWrote() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(try run(e, ["identity", "add", "--name", "Work", "--no-desktop"]).status == 0)
        let logFile = e.home.paths.logsDir.appending(path: "sync.log")
        // The note as Claude Code sees it: through the project's memory link in the account's own folder.
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "atelier").path)
        try Data("# deploy\n".utf8).write(to: link.appending(path: "deploy.md"))
        try Data("# prices\n".utf8).write(to: link.appending(path: "prices.md"))
        try Data("# theirs\n".utf8).write(to: e.brain.memoryDir(forProject: "atelier").appending(path: "theirs.md"))
        for (file, tool) in [("deploy.md", "Write"), ("prices.md", "Edit")] {
            let noted = try run(e, ["touched", "--identity", "perso"], input: edit(link.appending(path: file).path, tool: tool))
            #expect(noted.status == 0 && noted.stdout.isEmpty && noted.stderr.isEmpty, "\(noted.stderr)")
        }
        #expect(try run(e, ["touched", "--identity", "work"], input: edit(e.brain.memoryDir(forProject: "atelier").appending(path: "theirs.md").path)).status == 0)

        #expect(try run(e, ["sync", "--identity", "perso"]).status == 0)
        let last = try #require(try BrainGit(brain: e.brain).log(limit: 1).first)
        #expect(last.authorName == "Perso")
        // With the lists of its projects, linked when it was set up, and of the memory's accounts: those are the account's too.
        #expect(Set(last.files) == ["memory/atelier/deploy.md", "memory/atelier/prices.md", ".brainmerge/projects.json", ".brainmerge/identities.json"])
        #expect(last.message == MemorySentence.message(name: "Perso", files: last.files))
        #expect(last.message == "Perso remembered 2 things about atelier")
        #expect(try String(contentsOf: logFile, encoding: .utf8).contains("perso: committed 4 files"))

        #expect(try run(e, ["sync", "--identity", "work"]).status == 0)
        let theirs = try #require(try BrainGit(brain: e.brain).log(limit: 1).first)
        #expect(theirs.authorName == "Work" && theirs.files == ["memory/atelier/theirs.md"])
        #expect(!(try String(contentsOf: logFile, encoding: .utf8)).contains("sentinel"))
    }

    /// Another git held the memory's index as the save ended: the save is made anyway, and the log says the index catches
    /// up at the next save, with a count and nothing else.
    @Test func aSaveMadeWhileAnotherGitHeldTheIndexIsLogged() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let notes = e.brain.memoryDir(forProject: "atelier")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# deploy\n".utf8).write(to: notes.appending(path: "deploy.md"))
        #expect(try run(e, ["touched", "--identity", "perso"], input: edit(notes.appending(path: "deploy.md").path)).status == 0)
        FileManager.default.createFile(atPath: e.brain.gitDir.appending(path: "index.lock").path, contents: nil)

        let sync = try run(e, ["sync", "--identity", "perso"])
        #expect(sync.status == 0 && sync.stdout.isEmpty)
        // The note, and the lists of projects and accounts written when the account was set up.
        #expect(try BrainGit(brain: e.brain).log(limit: 1).first?.files.contains("memory/atelier/deploy.md") == true)
        let log = try String(contentsOf: e.home.paths.logsDir.appending(path: "sync.log"), encoding: .utf8)
        #expect(log.contains("perso: committed 3 files"))
        #expect(log.contains("perso: another git held the memory's index, it catches up with 3 files at the next save"), "\(log)")
    }

    /// A memory whose save waits (the person's own merge is stopped there, for days maybe) never stops the account's
    /// saves in its other memories: each memory is saved on its own, and the log names the one that waits.
    @Test func eachMemoryIsSavedOnItsOwn() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let clients = Brain(root: try e.manager.addBrain(name: "Clients", path: nil, language: .en).url)
        for brain in [e.brain, clients] {
            let notes = brain.memoryDir(forProject: "acme")
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            try Data("# note\n".utf8).write(to: notes.appending(path: "note.md"))
            try TouchedLedger(brain: brain, slug: "perso").append("memory/acme/note.md")
        }
        // Its own memory, listed first, is in the middle of the person's merge.
        try Data("0000000000000000000000000000000000000000\n".utf8).write(to: e.brain.gitDir.appending(path: "MERGE_HEAD"))

        #expect(try run(e, ["sync", "--identity", "perso"]).status == 0)
        let saved = try #require(try BrainGit(brain: clients).log(limit: 1).first)
        #expect(saved.authorName == "Perso" && saved.files == ["memory/acme/note.md"])
        #expect(TouchedLedger.claimed(in: e.brain).contains("memory/acme/note.md"), "the waiting memory keeps its list")
        let log = try String(contentsOf: e.home.paths.logsDir.appending(path: "sync.log"), encoding: .utf8)
        #expect(log.contains("perso: Shared: \(BrainmergeError.gitOperationUnfinished)"), "\(log)")
        #expect(log.contains("perso: committed 1 file"), "\(log)")
        // One memory that waits is enough for the app to say the account's saves are stuck.
        #expect(SaveStatusStore(paths: e.home.paths).read(slug: "perso")?.outcome == .failed)
        #expect(SaveStatusStore(paths: e.home.paths).read(slug: "perso")?.reason == .locked)
    }

    /// A note that looks like it holds a key is not committed, and nothing that could carry the key is written anywhere:
    /// not the log, not the held list, not the doctor. Its neighbor is saved.
    @Test func aKeyShapedNoteIsHeldBackAndNeverWrittenOut() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let value = SecretFixtures.gitHub
        let notes = e.brain.memoryDir(forProject: "acme-api")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Deploy\n\nPush with \(value)\n".utf8).write(to: notes.appending(path: "deploy.md"))
        try Data("# Prices\n".utf8).write(to: notes.appending(path: "prices.md"))
        for file in ["deploy.md", "prices.md"] {
            #expect(try run(e, ["touched", "--identity", "perso"], input: edit(notes.appending(path: file).path)).status == 0)
        }
        let sync = try run(e, ["sync", "--identity", "perso"])
        #expect(sync.status == 0 && sync.stdout.isEmpty)
        #expect(try BrainGit(brain: e.brain).log(limit: 1).first?.files.filter { $0.hasPrefix("memory/") } == ["memory/acme-api/prices.md"])
        let log = try String(contentsOf: e.home.paths.logsDir.appending(path: "sync.log"), encoding: .utf8)
        #expect(log.contains("perso: held back 1 file (looks like a key)"))
        let held = try String(contentsOf: HeldStore(paths: e.home.paths, memoryID: "shared").file, encoding: .utf8)
        #expect(held.contains("memory/acme-api/deploy.md"))
        let doctor = try run(e, ["doctor"])
        #expect(doctor.stdout.contains("acme-api/deploy.md, line 3, looks like a GitHub token"))
        // The app learns that a note waits, with a code: never which note, never the line.
        #expect(SaveStatusStore(paths: e.home.paths).read(slug: "perso")?.outcome == .held)
        #expect(SaveStatusStore(paths: e.home.paths).read(slug: "perso")?.reason == .heldBack)
        let status = try String(contentsOf: e.home.paths.appSupport.appending(path: "saves/perso.json"), encoding: .utf8)
        #expect(!status.contains("deploy") && !status.contains("acme"))
        for text in [log, held, status, doctor.stdout, doctor.stderr, sync.stderr, try run(e, ["doctor", "--json"]).stdout] {
            #expect(!text.contains(value) && !text.contains(String(value.suffix(12))) && !text.contains("Push with"))
        }
    }

    /// The PostToolUse hook runs after every edit: it prints nothing and never fails, whatever it is given.
    @Test func touchedPrintsNothingAndAlwaysExitsZero() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let note = e.brain.memoryDir(forProject: "atelier").appending(path: "n.md").path
        let before = TouchedLedger.claimed(in: e.brain)
        for (arguments, input) in [(["touched", "--identity", "nope"], edit(note)),
                                   (["touched", "--identity", "../../x"], edit(note)),
                                   (["touched", "--identity", "perso"], "{oops"),
                                   (["touched", "--identity", "perso"], ""),
                                   (["touched", "--identity", "perso"], #"{"tool_input":{"notebook_path":"/x.ipynb"}}"#),
                                   (["touched", "--identity", "perso"], edit(e.home.url.appending(path: "elsewhere.md").path))] {
            let result = try run(e, arguments, input: input)
            #expect(result.status == 0 && result.stdout.isEmpty, "\(arguments) \(input): \(result.stdout) \(result.stderr)")
        }
        #expect(TouchedLedger.claimed(in: e.brain) == before, "none of these adds a path")
        #expect(!FileManager.default.fileExists(atPath: e.home.url.appending(path: "x").path))
        try FileManager.default.removeItem(at: e.brain.root)
        #expect(try run(e, ["touched", "--identity", "perso"], input: edit(note)).status == 0)
    }

    /// Without --hook, the current folder is linked and the command says so.
    @Test func wireLinksTheCurrentFolder() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let folder = e.home.url.appending(path: "kayak", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let env = ["BRAINMERGE_HOME": e.home.url.path, "BRAINMERGE_CLAUDE_APP": e.claude.url.path]
        let result = try Shell().run(Products.brainmerge.path, ["wire", "--identity", "perso"], cwd: folder, environment: env)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("kayak"))
        // The folder as the process sees it (the temporary folder is behind /var, a link to /private/var).
        let slugs = try FileManager.default.contentsOfDirectory(atPath: e.primaryProfile.projectsDir.path).filter { $0.hasSuffix("-kayak") }
        #expect(slugs.count == 1)
        let link = e.primaryProfile.projectsDir.appending(path: slugs.first ?? "none").appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "kayak").path)
        #expect(try Shell().run(Products.brainmerge.path, ["wire", "--identity", "nope"], cwd: folder, environment: env).status != 0)
    }

    @Test func brainAddListForgetAndIdentityBrain() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        let add = try run(e, ["brain", "add", "--name", "Work"])
        #expect(add.status == 0, "\(add.stderr)")
        let list = try run(e, ["brain", "list"])
        #expect(list.stdout.contains("shared") && list.stdout.contains("work") && list.stdout.contains("Brain-work"))
        #expect(try run(e, ["identity", "add", "--name", "Client", "--brain", "work"]).status == 0)
        #expect(try e.store.load().identity(slug: "client")?.brain == "work")
        #expect(try run(e, ["identity", "add", "--name", "Solo", "--own-brain"]).status == 0)
        #expect(try e.store.load().brains.map(\.id) == ["shared", "work", "solo"])
        #expect(try run(e, ["brain", "forget", "work"]).status != 0)   // Client uses it
        #expect(try run(e, ["identity", "edit", "client", "--brain", "shared"]).status == 0)
        #expect(try e.store.load().identity(slug: "client")?.brain == "shared")
        #expect(try run(e, ["brain", "forget", "work"]).status == 0)
        #expect(try e.store.load().brains.map(\.id) == ["shared", "solo"])
        #expect(FileManager.default.fileExists(atPath: e.home.url.appending(path: "Brain-work/BRAIN.md").path))
        let dir = Brain(root: e.home.url.appending(path: "Brain-solo")).memoryDir(forProject: "atelier")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# note\n".utf8).write(to: dir.appending(path: "MEMORY.md"))
        #expect(try run(e, ["touched", "--identity", "solo"], input: edit(dir.appending(path: "MEMORY.md").path)).status == 0)
        #expect(try run(e, ["sync", "--identity", "solo"]).status == 0)
        #expect(try BrainGit(brain: Brain(root: e.home.url.appending(path: "Brain-solo"))).log(limit: 1).first?.authorName == "Solo")
        #expect(try BrainGit(brain: e.brain).log(limit: 1).isEmpty)
        #expect(try run(e, ["brain", "timeline", "--brain", "solo"]).stdout.contains("Solo"))
    }

    @Test func usageReadsAProfileDirectly() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let project = e.primaryProfile.projectsDir.appending(path: "-Users-demo-website", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = #"{"type":"assistant","cwd":"/Users/demo/website","timestamp":"\#(stamp)","message":{"id":"msg_1","model":"claude-fable-5-1","usage":{"input_tokens":3,"cache_creation_input_tokens":10,"cache_read_input_tokens":100,"output_tokens":42}}}"#
        try Data((line + "\n").utf8).write(to: project.appending(path: "s.jsonl"))
        let cache = e.home.url.appending(path: "usage-cache.json").path
        let result = try run(e, ["usage", "--profile", e.primaryProfile.directory.path, "--cache", cache, "--json", "--timing"])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("\"today\" : 42"))
        #expect(result.stderr.contains("timing:"))
        #expect(try run(e, ["usage", "--identity", "nobody"]).status != 0)
    }

    @Test func uninstallNeedsYes() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        let dry = try run(e, ["uninstall"])
        #expect(dry.status != 0)
        #expect(dry.stdout.contains("--yes") && dry.stdout.contains(e.brain.root.path))
        #expect(FileManager.default.fileExists(atPath: e.home.paths.stateFile.path))
        let done = try run(e, ["uninstall", "--yes"])
        #expect(done.status == 0, "\(done.stderr)")
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.stateFile.path))
        #expect(FileManager.default.fileExists(atPath: e.brain.brainMD.path))
    }

    /// The email Claude Code records is shown in the window only: the command line never prints it.
    @Test func theCommandLineNeverPrintsTheClaudeCodeEmail() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let email = "ruben.sentinel@example.com"
        let file = e.home.url.appending(path: ".claude.json")
        try Data(#"{"projects":{"\#(e.atelier)":{}},"oauthAccount":{"emailAddress":"\#(email)","displayName":"Ruben"}}"#.utf8).write(to: file)
        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        // Only its Claude Code folder matters here: no app is built, so nothing is registered with Launch Services.
        #expect(try run(e, ["identity", "add", "--name", "Client", "--no-desktop"]).status == 0)
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        let client = CLIProfile(directory: e.home.paths.cliProfile(slug: "client", isPrimary: false))
        try Data(#"{"oauthAccount":{"emailAddress":"client.sentinel@example.com"}}"#.utf8).write(to: client.accountFile)
        for arguments in [["doctor"], ["doctor", "--json"], ["identity", "list"], ["identity", "list", "--json"], ["brain", "status"]] {
            let result = try run(e, arguments)
            let output = result.stdout + result.stderr
            #expect(!output.contains("sentinel@example.com"), "\(arguments)")
        }
        #expect(!(try String(contentsOf: e.home.paths.stateFile, encoding: .utf8)).contains("sentinel"))
    }

    /// The primary is Claude itself: never a tinted copy, only its own app, and only the primary has one.
    @Test func thePrimaryGetsItsOwnAppNeverACopy() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        let copy = try run(e, ["identity", "edit", "perso", "--icon", "distinct"])
        #expect(copy.status != 0)
        #expect(copy.stderr.contains("never makes a copy") && copy.stderr.contains("--own-app on"))
        #expect(try run(e, ["identity", "edit", "perso", "--own-app", "maybe"]).status != 0)
        #expect(try run(e, ["identity", "add", "--name", "Client", "--no-desktop"]).status == 0)
        let secondary = try run(e, ["identity", "edit", "client", "--own-app", "on"])
        #expect(secondary.status != 0 && secondary.stderr.contains("primary"))
        #expect(try run(e, ["identity", "edit", "perso", "--own-app", "off"]).status == 0)
        #expect(try e.store.load().primary?.ownApp == false)
        #expect(try e.store.load().identity(slug: "client")?.ownApp == nil)
    }

    /// `brain health` mirrors the Memory screen's Tidy tab: the same groups and sentences, and a JSON shape that stays put,
    /// with paths inside the memory only.
    @Test func brainHealthMirrorsTheTidyTab() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["adopt-primary", "--name", "Perso"]).status == 0)
        let calm = try run(e, ["brain", "health"])
        #expect(calm.status == 0 && calm.stdout == "Nothing to tidy. Every note is where the next session will find it.\n")

        for (path, text) in [("memory/lumalab/look.md", "# look\n"), ("memory/lumalab/palette.md", "# palette\n"),
                             ("memory/scratch-2026-09-23-5050ce/lumalab-colors.md", "# colors\n")] {
            let url = e.brain.root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let text = try run(e, ["brain", "health"])
        #expect(text.status == 0)
        #expect(text.stdout == """
        Notes Claude will not load
          lumalab has 2 notes and no index, so no session loads them.
            look.md, palette.md

        Notes in one-off folders
          1 note sits in a quick session's folder that no later session reads.
            scratch-2026-09-23-5050ce

        """)

        let json = try run(e, ["brain", "health", "--json"])
        #expect(json.status == 0)
        #expect(!json.stdout.contains(e.home.url.path))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["count", "groups", "projects"])
        #expect(object["count"] as? Int == 2)
        #expect((object["projects"] as? [String])?.contains("lumalab") == true)
        let groups = try #require(object["groups"] as? [[String: Any]])
        #expect(groups.map { $0["id"] as? String } == ["notLoaded", "oneOff"])
        for group in groups { #expect(Set(group.keys) == ["id", "title", "items"]) }
        let items = groups.flatMap { $0["items"] as? [[String: Any]] ?? [] }
        for item in items { #expect(Set(item.keys) == ["kind", "project", "sentence", "detail", "files", "lines", "suggested"]) }
        #expect(items.map { $0["kind"] as? String } == ["noIndex", "oneOffNotes"])
        #expect(items[0]["project"] as? String == "lumalab" && items[0]["lines"] is NSNull)
        #expect(items[0]["files"] as? [String] == ["memory/lumalab/look.md", "memory/lumalab/palette.md"])
        #expect(items[1]["suggested"] as? [String] == ["lumalab"])
        #expect(try run(e, ["brain", "health", "--brain", "nope"]).status != 0)
    }

    @Test func versionMatchesTheApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == BrainmergeInfo.version)
        #expect(BrainmergeInfo.version == "0.5.0")
    }
}
