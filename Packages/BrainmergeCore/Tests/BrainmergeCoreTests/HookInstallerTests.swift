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
        #expect(cmd == #"test -x "/Users/r/.local/bin/brainmerge" && "/Users/r/.local/bin/brainmerge" sync --identity client; exit 0"#)
        #expect(cmd.contains(HookInstaller.marker))
        let wire = HookInstaller.wireCommand(cliPath: "/Users/r/.local/bin/brainmerge", slug: "client")
        #expect(wire == #"test -x "/Users/r/.local/bin/brainmerge" && "/Users/r/.local/bin/brainmerge" wire --identity client --hook; exit 0"#)
        #expect(HookInstaller.Event.allCases.map(\.marker) == ["sync --identity", "wire --identity", "touched --identity"])
        #expect(HookInstaller.Event.allCases.map(\.rawValue) == ["Stop", "SessionStart", "PostToolUse"])
    }

    /// Claude Code runs a hook through the shell: when the app was trashed or moved, the command finds nothing to run and
    /// still ends with 0, so no session of any account is ever blocked or shows an error.
    @Test func theCommandExitsZeroWhenTheCommandLineIsGone() throws {
        let home = try TempHome(); defer { home.remove() }
        let gone = home.url.appending(path: "Applications/Brainmerge.app/Contents/MacOS/brainmerge-cli").path
        for command in [HookInstaller.syncCommand(cliPath: gone, slug: "client"), HookInstaller.wireCommand(cliPath: gone, slug: "client")] {
            let result = try Shell().run("/bin/sh", ["-c", command])
            #expect(result.status == 0, "\(command): \(result.stderr)")
            #expect(result.stdout.isEmpty && result.stderr.isEmpty)
        }
        // A command line that fails does not fail the session either.
        let failing = home.url.appending(path: "failing")
        try Data("#!/bin/sh\nexit 3\n".utf8).write(to: failing)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failing.path)
        #expect(try Shell().run("/bin/sh", ["-c", HookInstaller.syncCommand(cliPath: failing.path, slug: "client")]).status == 0)
    }

    /// The path is taken literally by the shell, whatever characters a home folder's name holds.
    @Test func theCommandLinePathIsNeverExpandedByTheShell() throws {
        let home = try TempHome(); defer { home.remove() }
        let dir = home.url.appending(path: #"odd "name" $HOME `x` \ it's"#, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cli = dir.appending(path: "brainmerge")
        let marker = home.url.appending(path: "ran")
        try Data("#!/bin/sh\necho \"$@\" > '\(marker.path)'\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let result = try Shell().run("/bin/sh", ["-c", HookInstaller.syncCommand(cliPath: cli.path, slug: "client")])
        #expect(result.status == 0)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "sync --identity client\n")
    }

    /// Both of Brainmerge's hooks, installed twice: one entry each, the SessionStart one bounded to 5 seconds.
    @Test func stopAndSessionStartAreInstalledIdempotently() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let wire = HookInstaller.wireCommand(cliPath: "/Users/r/.local/bin/brainmerge", slug: "client")
        for _ in 0..<2 {
            try HookInstaller.install(settingsFile: file, event: .stop, command: cmd)
            try HookInstaller.install(settingsFile: file, event: .sessionStart, command: wire, timeout: 5)
        }
        let r = try root(file)
        #expect(HookInstaller.commands(r, event: .stop) == [cmd])
        #expect(HookInstaller.commands(r, event: .sessionStart) == [wire])
        let entry = try #require(((r["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])?.first)
        #expect(entry["matcher"] == nil)
        let hook = try #require((entry["hooks"] as? [[String: Any]])?.first)
        #expect(hook["timeout"] as? Int == 5 && hook["type"] as? String == "command")
        let stop = try #require((((r["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        #expect(stop["timeout"] == nil)
    }

    /// After each file edit, the account notes what it wrote: only for the edit tools that name a file, bounded like
    /// SessionStart, since the session waits for it.
    @Test func anAccountGetsAPostToolUseHookForItsEdits() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let cli = "/Users/r/.local/bin/brainmerge"
        #expect(HookInstaller.touchedCommand(cliPath: cli, slug: "client")
                == #"test -x "/Users/r/.local/bin/brainmerge" && "/Users/r/.local/bin/brainmerge" touched --identity client; exit 0"#)
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        let entries = try #require((try root(file)["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["matcher"] as? String == "Write|Edit|MultiEdit")
        let hook = try #require((entries[0]["hooks"] as? [[String: Any]])?.first)
        #expect(hook["command"] as? String == HookInstaller.touchedCommand(cliPath: cli, slug: "client"))
        #expect(hook["timeout"] as? Int == 5)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .current)
        // Accounts set up before it only had Stop and SessionStart: out of date until the launch or a repair adds it.
        var r = try root(file)
        var hooks = try #require(r["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "PostToolUse")
        r["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: r).write(to: file)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .outdated)
        let gone = home.url.appending(path: "gone/brainmerge").path
        #expect(try Shell().run("/bin/sh", ["-c", HookInstaller.touchedCommand(cliPath: gone, slug: "client")]).status == 0)
    }

    /// What every account gets (attach, repair, launch): the Stop hook as is, and the SessionStart hook with no matcher,
    /// bounded to 5 seconds, since the session waits for it.
    @Test func anAccountGetsStopAndABoundedSessionStart() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let cli = "/Users/r/.local/bin/brainmerge"
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        let hooks = try #require(try root(file)["hooks"] as? [String: Any])
        let start = try #require((hooks["SessionStart"] as? [[String: Any]])?.first)
        #expect(start.keys.sorted() == ["hooks"])
        let wire = try #require((start["hooks"] as? [[String: Any]])?.first)
        #expect(wire["command"] as? String == HookInstaller.wireCommand(cliPath: cli, slug: "client"))
        #expect(wire["timeout"] as? Int == 5)
        let stop = try #require(((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        #expect(stop["command"] as? String == HookInstaller.syncCommand(cliPath: cli, slug: "client"))
        #expect(stop["timeout"] == nil)
    }

    /// Two copies of Brainmerge's hook would run twice each turn: out of date, and a repair keeps one.
    @Test func aDuplicatedHookIsOutdated() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let cli = "/Users/r/.local/bin/brainmerge"
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        var r = try root(file)
        var hooks = try #require(r["hooks"] as? [String: Any])
        hooks["Stop"] = [["hooks": [["type": "command", "command": cmd]]], ["hooks": [["type": "command", "command": cmd]]]]
        r["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: r).write(to: file)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .outdated)
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        #expect(HookInstaller.commands(try root(file), event: .stop) == [cmd])
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .current)
    }

    /// A hook written by an older Brainmerge (the bare path, no guard) is replaced where it stands; a second copy of it
    /// goes, since it would run twice; the person's own hooks around it stay as they are.
    @Test func anOldFormatEntryIsUpgradedInPlace() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let old = #"\"/Users/r/.local/bin/brainmerge\" sync --identity client"#
        let existing = """
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"cd vault && git push"},{"type":"command","command":"\(old)"},{"type":"command","command":"live-off"}]},{"hooks":[{"type":"command","command":"\(old)"}]},{"hooks":[]}],"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo hello"}]}]}}
        """
        try Data(existing.utf8).write(to: file)
        try HookInstaller.install(settingsFile: file, event: .stop, command: cmd)
        let r = try root(file)
        #expect(HookInstaller.commands(r, event: .stop) == ["cd vault && git push", cmd, "live-off"])
        // The second copy's entry goes with it; an empty entry of the person's own stays.
        #expect(((r["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 2)
        #expect(HookInstaller.commands(r, event: .sessionStart) == ["echo hello"])
        let session = ((r["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])?.first
        #expect(session?["matcher"] as? String == "startup")
    }

    /// A matcher belongs to Brainmerge's own entry: changing it never changes the matcher of a person's hook that shares the entry.
    @Test func aMatcherIsSetOnBrainmergesOwnEntryOnly() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let touched = #"test -x "/b/brainmerge" && "/b/brainmerge" touched --identity client; exit 0"#
        let existing = """
        {"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"},{"type":"command","command":"\\"/b/brainmerge\\" touched --identity client"}]}]}}
        """
        try Data(existing.utf8).write(to: file)
        try HookInstaller.install(settingsFile: file, event: .postToolUse, command: touched, matcher: "Write|Edit")
        try HookInstaller.install(settingsFile: file, event: .postToolUse, command: touched, matcher: "Write|Edit")
        let entries = try #require((try root(file)["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])
        #expect(entries.count == 2)
        #expect(entries[0]["matcher"] as? String == "Bash")
        #expect((entries[0]["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } == ["echo mine"])
        #expect(entries[1]["matcher"] as? String == "Write|Edit")
        #expect((entries[1]["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } == [touched])
        // Its own entry is updated where it stands.
        try HookInstaller.install(settingsFile: file, event: .postToolUse, command: touched, matcher: "Write")
        let again = try #require((try root(file)["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])
        #expect(again.count == 2 && again[1]["matcher"] as? String == "Write")
    }

    @Test func removeClearsEveryBrainmergeHookAndKeepsTheOthers() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"live-off"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"echo hello"}]}]}}"#.utf8).write(to: file)
        try HookInstaller.install(settingsFile: file, event: .stop, command: cmd)
        try HookInstaller.install(settingsFile: file, event: .sessionStart, command: HookInstaller.wireCommand(cliPath: "/b/brainmerge", slug: "client"), timeout: 5)
        try HookInstaller.install(settingsFile: file, event: .postToolUse, command: #""/b/brainmerge" touched --identity client"#, matcher: "Write")
        try HookInstaller.remove(settingsFile: file)
        let r = try root(file)
        #expect(HookInstaller.commands(r, event: .stop) == ["live-off"])
        #expect(HookInstaller.commands(r, event: .sessionStart) == ["echo hello"])
        #expect((r["hooks"] as? [String: Any])?["PostToolUse"] == nil)
        #expect(HookInstaller.health(settingsFile: file, cliPath: "/b/brainmerge", slug: "client") == .missing)
    }

    /// What Settings and the doctor say about an account's hooks.
    @Test func healthSaysCurrentOutdatedOrMissing() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "settings.json")
        let cli = "/Users/r/.local/bin/brainmerge"
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .missing)
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"/Users/r/.local/bin/brainmerge\" sync --identity client"}]}]}}"#.utf8).write(to: file)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .outdated)
        try HookInstaller.installAll(settingsFile: file, cliPath: cli, slug: "client")
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .current)
        #expect(try HookInstaller.isInstalled(settingsFile: file))
        // Written for another command line path, or another account: out of date.
        #expect(HookInstaller.health(settingsFile: file, cliPath: "/elsewhere/brainmerge", slug: "client") == .outdated)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "other") == .outdated)
        try Data("{oops".utf8).write(to: file)
        #expect(HookInstaller.health(settingsFile: file, cliPath: cli, slug: "client") == .missing)
    }

    @Test func createsFileWhenMissing() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: ".claude-client/settings.json")
        try HookInstaller.install(settingsFile: file, command: cmd)
        #expect(try HookInstaller.isInstalled(settingsFile: file))
        #expect(try HookInstaller.commands(root(file), event: .stop) == [cmd])
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
        #expect(HookInstaller.commands(r, event: .stop) == ["cd vault && git push", "live-off", cmd])
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
        #expect(try HookInstaller.commands(root(file), event: .stop) == ["live-off"])
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
