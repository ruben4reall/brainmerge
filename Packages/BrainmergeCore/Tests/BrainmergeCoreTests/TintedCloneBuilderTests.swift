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

    /// The copy is modified and re-signed; the Claude it was copied from never is: every file of it, its signature
    /// included, is byte for byte the same after the build.
    @Test func theInstalledClaudeIsLeftUntouched() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        // Signed under an identifier of its own, as Anthropic signs Claude: a re-signature by the builder would show.
        try Shell().check("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "com.anthropic.claude.untouched", claude.url.path])
        func snapshot() throws -> [String: Data] {
            var files: [String: Data] = [:]
            let enumerator = try #require(FileManager.default.enumerator(at: claude.url, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files[url.path] = try Data(contentsOf: url)
            }
            return files
        }
        let before = try snapshot()
        #expect(before.keys.contains { $0.hasSuffix("_CodeSignature/CodeResources") })
        let icon = home.url.appending(path: "blue.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .blue, output: icon)
        try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: Identity(slug: "client", name: "Client", tint: .blue, iconMode: .tintedClone), claude: claude, icon: icon, register: false)
        #expect(try snapshot() == before)
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

    @Test func aClaudeWithABrokenSignatureIsNeverCopied() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        // Signed, then tampered with: the signature no longer matches the binary.
        try Shell().check("/usr/bin/codesign", ["--force", "--sign", "-", claude.url.path])
        let handle = try FileHandle(forWritingTo: claude.executable)
        try handle.seekToEnd(); handle.write(Data("\n# tampered\n".utf8)); try handle.close()
        let builder = TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
        let icon = try FakeIcon.orangePNG(in: home.url)
        #expect(throws: BrainmergeError.claudeAppTampered(claude.url.path)) {
            try builder.build(for: Identity(slug: "client", name: "Client"), claude: claude, icon: icon, register: false)
        }
        #expect(!FileManager.default.fileExists(atPath: home.paths.tintedClone(name: "Client").path))
    }

    @Test func aClaudeWhoseBundleWasNeverSignedIsNotCalledTampered() throws {
        // A compiled executable is signed by the linker, but the bundle around it has no signature at all:
        // that is not a broken signature, and the copy goes ahead (the demo's fake Claude is exactly this).
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let source = home.url.appending(path: "main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: source)
        try FileManager.default.removeItem(at: claude.executable)
        try Shell().check("/usr/bin/cc", ["-o", claude.executable.path, source.path])
        let icon = home.url.appending(path: "blue.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .blue, output: icon)
        let app = try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: Identity(slug: "client", name: "Client", iconMode: .tintedClone), claude: claude, icon: icon, register: false)
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func aFailedCopyLeavesTheOldAppAndNoBuildingFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let icon = home.url.appending(path: "i.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .green, output: icon)
        let identity = Identity(slug: "client", name: "Client", iconMode: .tintedClone)
        let app = try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: identity, claude: claude, icon: icon, register: false)
        let failingCopy = Shell { executable, arguments, cwd, environment in
            if executable == "/bin/cp" { return ShellResult(status: 1, stdout: "", stderr: "No space left on device") }
            return try Shell().run(executable, arguments, cwd: cwd, environment: environment)
        }
        #expect(throws: (any Error).self) {
            try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher, shell: failingCopy)
                .build(for: identity, claude: claude, icon: icon, register: false)
        }
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/MacOS/Claude-bin").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.paths.launchersDir.path) == ["Client (Claude).app"])
    }

    /// The copy is made, then signing fails: the half-built copy goes, the old app stays as it was.
    @Test func aFailedSignatureLeavesTheOldAppAndNoBuildingFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try FakeClaudeApp.make(in: home.url)
        let icon = home.url.appending(path: "i.icns")
        try IconGenerator.tintedICNS(from: claude.icon, tint: .green, output: icon)
        let identity = Identity(slug: "client", name: "Client", iconMode: .tintedClone)
        let app = try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher)
            .build(for: identity, claude: claude, icon: icon, register: false)
        let marker = app.appending(path: "Contents/Resources/old-build")
        try Data().write(to: marker)
        let copied = ShellCalls()
        let failingSign = Shell { executable, arguments, cwd, environment in
            if executable == "/usr/bin/codesign", arguments.contains("--sign") { return ShellResult(status: 1, stdout: "", stderr: "failed") }
            if executable == "/bin/cp" { copied.record(arguments) }
            return try Shell().run(executable, arguments, cwd: cwd, environment: environment)
        }
        #expect(throws: (any Error).self) {
            try TintedCloneBuilder(paths: home.paths, launcherBinary: Products.launcher, shell: failingSign)
                .build(for: identity, claude: claude, icon: icon, register: false)
        }
        #expect(!copied.all.isEmpty)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.paths.launchersDir.path) == ["Client (Claude).app"])
    }
}
