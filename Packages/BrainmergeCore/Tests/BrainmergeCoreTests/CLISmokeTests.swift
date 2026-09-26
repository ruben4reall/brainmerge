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
        let sync = try run(e, ["sync", "--identity", "client"])
        #expect(sync.status == 0)
        let log = try BrainGit(brain: e.brain).log(limit: 1)
        #expect(log.first?.authorName == "Client")
        #expect(log.first?.authorEmail == "client@brainmerge.local")
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

    /// Like Claude Code runs a hook: the session's JSON on the standard input, which is then closed.
    func run(_ e: ManagerEnv, _ arguments: [String], input: String) throws -> ShellResult {
        let process = Process()
        process.executableURL = Products.brainmerge
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["BRAINMERGE_HOME": e.home.url.path, "BRAINMERGE_CLAUDE_APP": e.claude.url.path]) { $1 }
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

    @Test func versionMatchesTheApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == BrainmergeInfo.version)
        #expect(BrainmergeInfo.version == "0.5.0")
    }
}
