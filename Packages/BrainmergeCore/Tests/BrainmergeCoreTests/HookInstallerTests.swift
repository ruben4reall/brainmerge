import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct HookInstallerTests {
    let cmd = HookInstaller.syncCommand(cliPath: "/Users/r/.local/bin/brainmerge", slug: "client")

    func root(_ file: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    }

    @Test func commandShape() {
        #expect(cmd == "\"/Users/r/.local/bin/brainmerge\" sync --identity client")
        #expect(cmd.contains(HookInstaller.marker))
    }

    @Test func createsFileWhenMissing() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: ".claude-client/settings.json")
        try HookInstaller.install(settingsFile: file, command: cmd)
        #expect(try HookInstaller.isInstalled(settingsFile: file))
        #expect(try HookInstaller.stopCommands(root(file)) == [cmd])
    }

    @Test func mergesWithExistingHooksAndStaysIdempotent() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let existing = """
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"cd vault && git push"},{"type":"command","command":"live-off"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]}}
        """
        try Data(existing.utf8).write(to: file)
        try HookInstaller.install(settingsFile: file, command: cmd)
        try HookInstaller.install(settingsFile: file, command: cmd)
        let r = try root(file)
        #expect(r["model"] as? String == "opus")
        #expect(((r["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.count == 1)
        #expect(HookInstaller.stopCommands(r) == ["cd vault && git push", "live-off", cmd])
    }

    @Test func emptyFileAndInvalidJSON() throws {
        let home = try TempHome(); defer { home.remove() }
        let empty = home.url.appending(path: "empty.json")
        try Data().write(to: empty)
        try HookInstaller.install(settingsFile: empty, command: cmd)
        #expect(try HookInstaller.isInstalled(settingsFile: empty))
        let bad = home.url.appending(path: "bad.json")
        try Data("{oops".utf8).write(to: bad)
        #expect(throws: BrainmergeError.invalidJSON(bad.path)) {
            try HookInstaller.install(settingsFile: bad, command: cmd)
        }
    }

    @Test func removeKeepsOtherHooks() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"live-off"}]}]}}"#.utf8).write(to: file)
        try HookInstaller.install(settingsFile: file, command: cmd)
        try HookInstaller.remove(settingsFile: file)
        #expect(try HookInstaller.stopCommands(root(file)) == ["live-off"])
        #expect(try !HookInstaller.isInstalled(settingsFile: file))
    }

    @Test func writesReadableSlashesAndThroughSymlinks() throws {
        let home = try TempHome(); defer { home.remove() }
        let target = home.url.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: target)
        let link = home.url.appending(path: "settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try HookInstaller.install(settingsFile: link, command: cmd)
        let raw = try String(contentsOf: target, encoding: .utf8)
        #expect(raw.contains("/Users/r/.local/bin/brainmerge"))
        #expect(!raw.contains("\\/"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }
}
