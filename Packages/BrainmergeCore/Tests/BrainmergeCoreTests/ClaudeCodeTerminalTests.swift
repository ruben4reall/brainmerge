import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport

@Suite struct ClaudeCodeTerminalTests {
    /// A fake `claude` that prints what it got: the variable and its arguments.
    func fakeClaude(in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "claude")
        try Data("#!/bin/sh\necho \"dir=${CLAUDE_CONFIG_DIR-unset}\"\necho \"args=$*\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    func run(_ e: ManagerEnv, _ arguments: [String], path: String, executable: URL = Products.brainmerge, cwd: URL? = nil) throws -> ShellResult {
        // CLAUDE_CONFIG_DIR set in the caller: the primary must unset it, a secondary must replace it.
        try Shell().run(executable.path, arguments, cwd: cwd, environment: ["BRAINMERGE_HOME": e.home.url.path, "BRAINMERGE_CLAUDE_APP": e.claude.url.path,
                                                                         "PATH": path, "CLAUDE_CONFIG_DIR": "/elsewhere"])
    }

    @Test func codeRunsTheFirstClaudeOnPathWithTheAccountsProfile() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let bin = e.home.url.appending(path: "tools")
        try fakeClaude(in: bin)
        let work = try run(e, ["code", "work", "--resume", "x y"], path: "relative:\(bin.path):/usr/bin")
        #expect(work.status == 0, "\(work.stderr)")
        #expect(work.stdout.contains("dir=\(e.home.paths.cliProfile(slug: "work", isPrimary: false).path)"))
        #expect(work.stdout.contains("args=--resume x y"))
        // Output into a pipe, not a terminal: no tab title in it.
        #expect(!work.stdout.contains("\u{1B}]2;"))
        let primary = try run(e, ["code", "ruben"], path: bin.path)
        #expect(primary.stdout.contains("dir=unset"))
    }

    /// A relative entry runs whatever `claude` sits in the current folder: with one there and in tools/, nothing runs.
    @Test func noClaudeOnAnAbsolutePathExits127() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        try fakeClaude(in: e.home.url.appending(path: "tools"))
        try fakeClaude(in: e.home.url)
        let result = try run(e, ["code", "ruben"], path: "tools:.:", cwd: e.home.url)
        #expect(result.status == 127)
        #expect(!result.stdout.contains("dir="))
        #expect(result.stderr.contains("Claude Code is not installed or not on your PATH."))
    }

    @Test func resolveSkipsRelativeEntriesAndBrainmergesOwnLinks() {
        let ours = "/Applications/Brainmerge.app/Contents/MacOS/brainmerge-cli"
        #expect(ClaudeCodeTerminal.resolve(path: "tools:.::/b", isExecutable: { _ in true }, destination: { _ in nil }) == "/b/claude")
        // A claude on PATH that is one of Brainmerge's own links would run Brainmerge again, not Claude Code.
        #expect(ClaudeCodeTerminal.resolve(path: "/a:/b", isExecutable: { _ in true },
                                           destination: { $0 == "/a/claude" ? ours : nil }) == "/b/claude")
        #expect(ClaudeCodeTerminal.resolve(path: "/a", isExecutable: { _ in true }, destination: { _ in ours }) == nil)
    }

    @Test func envPrintsAQuotedExportOrAnUnset() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        #expect(try run(e, ["env", "ruben"], path: "/usr/bin").stdout == "unset CLAUDE_CONFIG_DIR\n")
        #expect(try run(e, ["env", "work"], path: "/usr/bin").stdout == "export CLAUDE_CONFIG_DIR='\(e.home.paths.cliProfile(slug: "work", isPrimary: false).path)'\n")
        #expect(ClaudeCodeTerminal.envLine(configDir: "/a/it's") == "export CLAUDE_CONFIG_DIR='/a/it'\\''s'")
    }

    @Test func aClaudeDashSlugNameBecomesCode() {
        #expect(ClaudeCodeTerminal.dispatch(["/Users/x/.local/bin/claude-work", "--resume", "x"], slugs: ["work"]) == ["code", "work", "--resume", "x"])
        #expect(ClaudeCodeTerminal.dispatch(["claude-other"], slugs: ["work"]) == [])
        #expect(ClaudeCodeTerminal.dispatch(["brainmerge", "doctor"], slugs: ["work"]) == ["doctor"])
    }

    @Test func calledThroughItsAccountLinkItRunsCode() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let bin = e.home.url.appending(path: "tools")
        try fakeClaude(in: bin)
        // A copy of the built command line under the app's layout: links only ever point at Brainmerge's own.
        let embedded = e.home.url.appending(path: "Brainmerge.app/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: embedded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Products.brainmerge, to: embedded)
        #expect(try CLIInstaller.linkAccount(paths: e.home.paths, slug: "work", target: embedded))
        let result = try run(e, ["--resume", "x"], path: "\(e.home.paths.localBin.path):\(bin.path)",
                             executable: CLIInstaller.accountLink(in: e.home.paths, slug: "work"))
        #expect(result.stdout.contains("args=--resume x"), "\(result.stderr)")
        #expect(result.stdout.contains("dir=\(e.home.paths.cliProfile(slug: "work", isPrimary: false).path)"))
    }

    @Test func accountLinksNeverReplaceAFileAndSkipAForeignLink() throws {
        let home = try TempHome(); defer { home.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: home.paths.localBin, withIntermediateDirectories: true)
        let mine = CLIInstaller.accountLink(in: home.paths, slug: "mine")
        try Data("x".utf8).write(to: mine)
        #expect(try !CLIInstaller.linkAccount(paths: home.paths, slug: "mine", target: Products.brainmerge))
        #expect(try String(contentsOf: mine, encoding: .utf8) == "x")
        let foreign = CLIInstaller.accountLink(in: home.paths, slug: "foreign")
        try fm.createSymbolicLink(atPath: foreign.path, withDestinationPath: "/usr/bin/true")
        CLIInstaller.unlinkAccount(paths: home.paths, slug: "foreign")
        CLIInstaller.unlinkAccount(paths: home.paths, slug: "mine")
        #expect(fm.fileExists(atPath: mine.path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: foreign.path)) == "/usr/bin/true")
        let embedded = home.url.appending(path: "Brainmerge.app/Contents/MacOS/brainmerge-cli")
        try fm.createDirectory(at: embedded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: embedded)
        #expect(try CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: embedded))
        CLIInstaller.unlinkAccount(paths: home.paths, slug: "work")
        #expect((try? fm.destinationOfSymbolicLink(atPath: CLIInstaller.accountLink(in: home.paths, slug: "work").path)) == nil)
    }

    func embeddedCLI(in home: TempHome, app: String = "Brainmerge.app") throws -> URL {
        let cli = home.url.appending(path: "\(app)/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }

    /// A link Brainmerge could not recognize later could never be removed: only its own command line is linked to.
    @Test func accountLinksPointOnlyAtBrainmergesCommandLine() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(try !CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: Products.brainmerge))
        #expect(!FileManager.default.fileExists(atPath: CLIInstaller.accountLink(in: home.paths, slug: "work").path))
    }

    /// Like the brainmerge link: from the disk image (about to go away) nothing is linked.
    @Test func noAccountLinkFromAReadOnlyDisk() throws {
        let home = try TempHome(); defer { home.remove() }
        let cli = try embeddedCLI(in: home)
        #expect(try !CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: cli, readOnly: { _ in true }))
        #expect(!FileManager.default.fileExists(atPath: CLIInstaller.accountLink(in: home.paths, slug: "work").path))
    }

    /// Someone else's claude-<slug> that points nowhere is still theirs: left as it is, never replaced.
    @Test func aBrokenForeignAccountLinkIsLeftAlone() throws {
        let home = try TempHome(); defer { home.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: home.paths.localBin, withIntermediateDirectories: true)
        let link = CLIInstaller.accountLink(in: home.paths, slug: "work")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent/other-tool")
        let cli = try embeddedCLI(in: home)
        #expect(try !CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: cli))
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == "/nonexistent/other-tool")
    }

    /// Brainmerge moved or trashed: its own link to the old place is pointed at the new one; a working one stays.
    @Test func aStaleAccountLinkOfOursIsRepointed() throws {
        let home = try TempHome(); defer { home.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: home.paths.localBin, withIntermediateDirectories: true)
        let link = CLIInstaller.accountLink(in: home.paths, slug: "work")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/Volumes/Gone/Brainmerge.app/Contents/MacOS/brainmerge-cli")
        let cli = try embeddedCLI(in: home)
        #expect(try CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: cli))
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == cli.resolvingSymlinksInPath().path)
        let other = try embeddedCLI(in: home, app: "Other/Brainmerge.app")
        #expect(try CLIInstaller.linkAccount(paths: home.paths, slug: "work", target: other))
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == cli.resolvingSymlinksInPath().path)
    }

    /// `brainmerge identity add` with the per-account commands on: the new account gets its command at once, pointed
    /// where the brainmerge link points.
    @Test func addingAnAccountLinksItsCommandWhenTheSwitchIsOn() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let cli = try embeddedCLI(in: e.home)
        try FileManager.default.createDirectory(at: e.home.paths.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: e.cliPath, withDestinationPath: cli.path)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Off"))
        #expect(!FileManager.default.fileExists(atPath: CLIInstaller.accountLink(in: e.home.paths, slug: "off").path))
        var state = try e.store.load()
        state.terminalCommands = true
        try e.store.save(state)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let link = CLIInstaller.accountLink(in: e.home.paths, slug: "work")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == cli.resolvingSymlinksInPath().path)
    }

    @Test func removingAnAccountRemovesItsLink() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let embedded = e.home.url.appending(path: "Brainmerge.app/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: embedded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: embedded)
        #expect(try CLIInstaller.linkAccount(paths: e.home.paths, slug: "work", target: embedded))
        try e.manager.remove(slug: "work", deleteData: false)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.accountLink(in: e.home.paths, slug: "work").path)) == nil)
    }

    @Test func titleIsSetOnlyForATerminal() {
        #expect(ClaudeCodeTerminal.title(name: "Work") == "\u{1B}]2;Claude: Work\u{07}")
        #expect(ClaudeCodeTerminal.title(name: "Wo\u{07}rk\u{1B}") == "\u{1B}]2;Claude: Work\u{07}")
    }
}
