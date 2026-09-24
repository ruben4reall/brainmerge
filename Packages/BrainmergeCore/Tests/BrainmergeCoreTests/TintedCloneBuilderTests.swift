import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct TintedCloneBuilderTests {
    @Test func clonesTintsAndWrapsExecutable() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let icon = home.url.appending(path: "blue.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .blue, output: icon)
        let identity = Identity(slug: "client", name: "Client", tint: .blue, iconMode: .tintedClone)
        let app = try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: identity, claude: claude, icon: icon, register: false)

        #expect(app.lastPathComponent == "Client (Claude).app")
        let plist = try Plist.read(app.appending(path: "Contents/Info.plist"))
        #expect(plist["CFBundleIconName"] == nil)
        #expect(plist["CFBundleName"] as? String == "Claude")
        let realBinary = app.appending(path: "Contents/MacOS/Claude-bin")
        #expect(FileManager.default.fileExists(atPath: realBinary.path))
        let data = try Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json"))
        #expect(try JSONDecoder().decode(LauncherConfig.self, from: data).claudeExecutable == realBinary.path)
        #expect(try IconGenerator.centerPixel(of: app.appending(path: "Contents/Resources/electron.icns")).blue > 0.3)

        let log = home.url.appending(path: "fake.log")
        let result = try Shell().run(app.appending(path: "Contents/MacOS/Claude").path, [],
                                     environment: ["BRAINMERGE_FAKE_LOG": log.path])
        #expect(result.status == 0)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("--user-data-dir=\(home.paths.desktopData(slug: "client", isPrimary: false).path)"))
        #expect(text.contains("CLAUDE_CONFIG_DIR=\(home.paths.cliProfile(slug: "client", isPrimary: false).path)"))
    }

    @Test func rebuildReplacesPreviousClone() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let icon = home.url.appending(path: "i.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .green, output: icon)
        let identity = Identity(slug: "client", name: "Client", iconMode: .tintedClone)
        let builder = TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
        _ = try builder.build(for: identity, claude: claude, icon: icon, register: false)
        _ = try builder.build(for: identity, claude: claude, icon: icon, register: false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.paths.launchersDir.path) == ["Client (Claude).app"])
    }
}
