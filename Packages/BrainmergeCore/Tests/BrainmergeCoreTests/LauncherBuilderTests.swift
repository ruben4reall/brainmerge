import Foundation
import Testing
import BrainmergeTestSupport
import LauncherGuard
@testable import BrainmergeCore

@Suite struct LauncherBuilderTests {
    @Test func buildsSignedBundleWithConfigAndPlist() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let identity = Identity(slug: "client", name: "ClientStudio", tint: .blue)
        let builder = LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
        let app = try builder.build(for: identity, claude: claude, icon: nil, register: false)

        #expect(app.path == home.paths.launcherApp(name: "ClientStudio").path)
        let plist = try Plist.read(app.appending(path: "Contents/Info.plist"))
        #expect(plist["CFBundleIdentifier"] as? String == "ch.rubencatalao.brainmerge.launch.client")
        #expect(plist["CFBundleExecutable"] as? String == "launcher")
        #expect(plist["CFBundleName"] as? String == "ClientStudio")
        let data = try Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json"))
        let config = try JSONDecoder().decode(LauncherConfig.self, from: data)
        #expect(config.configDir == home.paths.cliProfile(slug: "client", isPrimary: false).path)
        #expect(config.dataDir == home.paths.desktopData(slug: "client", isPrimary: false).path)
        #expect(config.claudeExecutable == claude.executable.path)
        #expect(try Shell().run("/usr/bin/codesign", ["--verify", app.path]).status == 0)
    }

    @Test func launcherExecutesClaudeWithProfileAndDataDir() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let identity = Identity(slug: "client", name: "Client")
        let app = try LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: identity, claude: claude, icon: nil, register: false)
        let log = home.url.appending(path: "fake.log")
        let result = try Shell().run(app.appending(path: "Contents/MacOS/launcher").path, ["--extra"],
                                     environment: ["BRAINMERGE_FAKE_LOG": log.path])
        #expect(result.status == 0)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("CLAUDE_CONFIG_DIR=\(home.paths.cliProfile(slug: "client", isPrimary: false).path)"))
        #expect(text.contains("--user-data-dir=\(home.paths.desktopData(slug: "client", isPrimary: false).path)"))
        #expect(text.contains("--extra"))
    }

    @Test func rebuildReplacesExistingBundle() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude1 = try FakeClaudeApp.make(in: home.url)
        let other = home.url.appending(path: "other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let claude2 = try FakeClaudeApp.make(in: other, version: "2.8000.0")
        let identity = Identity(slug: "client", name: "Client")
        let builder = LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
        _ = try builder.build(for: identity, claude: claude1, icon: nil, register: false)
        let app = try builder.build(for: identity, claude: claude2, icon: nil, register: false)
        let data = try Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json"))
        #expect(try JSONDecoder().decode(LauncherConfig.self, from: data).claudeExecutable == claude2.executable.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.paths.launchersDir.path) == ["Client.app"])
    }

    @Test func launcherRefusesToStartAnythingButClaude() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let identity = Identity(slug: "client", name: "Client")
        let app = try LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: identity, claude: claude, icon: nil, register: false)
        // Someone rewrites the launcher's config to point at another program: the launcher says no.
        let config = LauncherConfig(configDir: home.paths.cliProfile(slug: "client", isPrimary: false).path,
                                    dataDir: home.paths.desktopData(slug: "client", isPrimary: false).path,
                                    claudeExecutable: "/bin/echo")
        try JSONEncoder().encode(config).write(to: app.appending(path: "Contents/Resources/brainmerge.json"), options: .atomic)
        let result = try Shell().run(app.appending(path: "Contents/MacOS/launcher").path, [])
        #expect(result.status == 3)
        #expect(result.stderr.contains("only starts Claude"))
        // Relative folders are refused as well.
        let relative = LauncherConfig(configDir: "../elsewhere", dataDir: home.paths.desktopData(slug: "client", isPrimary: false).path, claudeExecutable: claude.executable.path)
        try JSONEncoder().encode(relative).write(to: app.appending(path: "Contents/Resources/brainmerge.json"), options: .atomic)
        #expect(try Shell().run(app.appending(path: "Contents/MacOS/launcher").path, []).status == 3)
    }

    // MARK: The primary's own app

    @Test func thePrimarysOpenerCarriesNoFoldersAndPinsClaude() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let identity = Identity(slug: "ruben", name: "Ruben", isPrimary: true, ownApp: true)
        let app = try LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .buildOpener(for: identity, claude: claude, icon: nil, register: false)

        #expect(app.path == home.paths.launcherApp(name: "Ruben").path)
        // Only the app to open: no Claude Code folder, no data folder, no executable to run directly.
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json"))) as? [String: Any]
        #expect(json?.keys.sorted() == ["openApp"])
        #expect(json?["openApp"] as? String == claude.url.path)
        let plist = try Plist.read(app.appending(path: "Contents/Info.plist"))
        #expect(plist["CFBundleIdentifier"] as? String == "ch.rubencatalao.brainmerge.launch.ruben")
        #expect(plist["CFBundleName"] as? String == "Ruben")
        #expect(plist["CFBundleExecutable"] as? String == "launcher")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist[OpenTarget.pinKey] as? String == claude.url.path)
        #expect(try Shell().run("/usr/bin/codesign", ["--verify", app.path]).status == 0)
    }

    /// A sandbox in which `/usr/bin/open` cannot start: the opener's refusal tests run in it, so even a launcher whose
    /// checks broke could never open an app from a test. Checked before use on a harmless program denied the same way.
    static let noOpen = #"(version 1)(allow default)(deny process-exec (literal "/usr/bin/open") (literal "/usr/bin/true"))"#

    func runWithoutOpen(_ executable: String) throws -> ShellResult {
        let sandbox = "/usr/bin/sandbox-exec"
        try #require(FileManager.default.isExecutableFile(atPath: sandbox), "the opener's tests only run where open can be denied")
        try #require(try Shell().run(sandbox, ["-p", Self.noOpen, "/usr/bin/true"]).status != 0, "the sandbox must deny what it lists")
        return try Shell().run(sandbox, ["-p", Self.noOpen, executable])
    }

    /// Never the success path: the fake Claude is never signed by Anthropic, so each case below is refused twice over
    /// (by the check it is about, and by the signature) and `open` is never reached. It runs where `open` cannot start
    /// anyway: a launcher that stopped refusing fails here with "cannot start", never by opening something.
    @Test func thePrimarysOpenerRefusesToOpenAnythingElse() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let identity = Identity(slug: "ruben", name: "Ruben", isPrimary: true, ownApp: true)
        let app = try LauncherBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .buildOpener(for: identity, claude: claude, icon: nil, register: false)
        let configFile = app.appending(path: "Contents/Resources/brainmerge.json")
        func launch(_ config: LauncherConfig) throws -> ShellResult {
            try JSONEncoder().encode(config).write(to: configFile, options: .atomic)
            let result = try runWithoutOpen(app.appending(path: "Contents/MacOS/launcher").path)
            #expect(!result.stderr.contains("cannot start"), "the launcher tried to open \(config.openApp ?? "")")
            return result
        }

        // Another Claude-looking app than the one pinned when the app was built.
        let otherDir = home.url.appending(path: "other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let other = try FakeClaudeApp.make(in: otherDir)
        let moved = try launch(LauncherConfig(openApp: other.url.path))
        #expect(moved.status == 3)
        #expect(moved.stderr.contains("only opens Claude") && moved.stderr.contains(OpenTarget.Refusal.notPinned.reason))

        // A relative path, and a path that climbs out with /../.
        let relative = try launch(LauncherConfig(openApp: "Claude.app"))
        #expect(relative.status == 3 && relative.stderr.contains(OpenTarget.Refusal.notAnApp.reason))
        let climbing = try launch(LauncherConfig(openApp: otherDir.path + "/../Claude.app"))
        #expect(climbing.status == 3 && climbing.stderr.contains(OpenTarget.Refusal.notAnApp.reason))

        // Folders next to the app to open: this app never runs Claude on folders of its own.
        var mixed = LauncherConfig(configDir: home.url.path + "/.claude-x", dataDir: home.url.path + "/data", claudeExecutable: claude.executable.path)
        mixed.openApp = claude.url.path
        let both = try launch(mixed)
        #expect(both.status == 3 && both.stderr.contains("only opens Claude"))

        // The pinned path, but the app there is not Claude any more.
        var plist = try Plist.read(claude.infoPlist)
        plist["CFBundleIdentifier"] = "com.example.notclaude"
        try Plist.write(plist, to: claude.infoPlist)
        let replaced = try launch(LauncherConfig(openApp: claude.url.path))
        #expect(replaced.status == 3 && replaced.stderr.contains(OpenTarget.Refusal.notClaude.reason))
    }

    /// What the opener runs once every check passed: `open -a` on the pinned Claude and nothing else, no argument of its
    /// own passed on, no Claude Code folder left in the environment.
    @Test func theOpenerAsksMacOSToOpenClaudeAndNothingMore() {
        let command = OpenTarget.command(opening: "/Applications/Claude.app")
        #expect(command.path == "/usr/bin/open")
        #expect(command.arguments == ["open", "-a", "/Applications/Claude.app"])
        #expect(command.unset == ["CLAUDE_CONFIG_DIR"])
    }

    /// The launcher runs exactly that command: its opener branch passes nothing else on.
    @Test func theLauncherRunsTheOpenCommandAsIs() throws {
        let main = SecurityGuardTests.repo.appending(path: "Packages/BrainmergeCore/Sources/launcher/main.swift")
        let text = try String(contentsOf: main, encoding: .utf8)
        let start = try #require(text.range(of: "if let app = config.openApp {"))
        let end = try #require(text.range(of: "\n}\n", range: start.upperBound..<text.endIndex))
        let branch = String(text[start.lowerBound..<end.upperBound])
        #expect(branch.contains("let command = OpenTarget.command(opening: app)"))
        #expect(branch.contains("for name in command.unset { unsetenv(name) }"))
        #expect(branch.contains("exec(command.path, command.arguments)"))
        #expect(!branch.contains("CommandLine") && !branch.contains("setenv(\"") && !branch.contains("\"/usr/bin/open\""))
    }
}
