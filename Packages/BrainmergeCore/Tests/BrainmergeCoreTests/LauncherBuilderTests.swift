import Foundation
import Testing
import BrainmergeTestSupport
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
}
