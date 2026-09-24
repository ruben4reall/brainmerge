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

    @Test func versionMatchesTheApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(try run(e, ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == BrainmergeInfo.version)
        #expect(BrainmergeInfo.version == "0.4.0")
    }
}
