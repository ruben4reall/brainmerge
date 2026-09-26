import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct DoctorTests {
    func doctor(_ e: ManagerEnv) -> Doctor {
        Doctor(paths: e.home.paths, store: e.store, claudeAppURL: e.claude.url, cliPath: e.cliPath)
    }

    @Test func missingGitIsNamedWithAppleInstaller() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let missing = GitAvailability(shell: Shell { _, _, _, _ in ShellResult(status: 2, stdout: "", stderr: "") }, isExecutable: { _ in false })
        let findings = Doctor(paths: e.home.paths, store: e.store, claudeAppURL: e.claude.url, cliPath: e.cliPath, git: missing).run()
        #expect(findings.contains(Doctor.Finding(level: .error, title: "git",
                                                 detail: "Apple's Command Line Tools are not installed. Run: xcode-select --install",
                                                 plain: "Apple's Command Line Tools are missing: the memory keeps its history with them.",
                                                 fix: .installAppleTools)))
        #expect(doctor(e).run().contains { $0.title == "git" && $0.level == .ok })
    }

    @Test func healthySetupHasNoErrors() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let findings = doctor(e).run()
        #expect(!findings.hasErrors)
        #expect(findings.contains { $0.title == "Claude.app" && $0.level == .ok && $0.detail.contains("2.7032.0") })
        #expect(findings.contains { $0.title == "Command line" && $0.level == .warning })
    }

    @Test func reportsMissingLauncherHookBlockAndBrokenLink() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Client"))
        try HookInstaller.remove(settingsFile: e.primaryProfile.settingsFile)
        try Data("# sans bloc\n".utf8).write(to: CLIProfile(directory: client.cliProfile(in: e.home.paths)).claudeMD)
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: e.home.url.appending(path: "gone"))

        let findings = doctor(e).run()
        #expect(findings.hasErrors)
        #expect(findings.contains { $0.title == "Client: launcher" && $0.level == .error })
        #expect(findings.contains { $0.title == "Perso: hooks" && $0.level == .warning && $0.detail.hasPrefix("missing") })
        #expect(findings.contains { $0.title == "Client: CLAUDE.md" && $0.level == .warning })
        #expect(findings.contains { $0.title == "Perso: memory atelier" && $0.level == .error })
    }

    /// One finding per account for its hooks: current, outdated (an older Brainmerge wrote them) or missing.
    @Test func saysWhetherEachAccountsHooksAreCurrent() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let hooks = { doctor(e).run().filter { $0.title.hasSuffix(": hooks") } }
        #expect(hooks().map(\.title) == ["Perso: hooks", "Client: hooks"])
        #expect(hooks().allSatisfy { $0.level == .ok && $0.detail == "current" })
        let settings = CLIProfile(directory: client.cliProfile(in: e.home.paths)).settingsFile
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"\#(e.cliPath)\" sync --identity client"}]}]}}"#.utf8).write(to: settings)
        let outdated = try #require(hooks().first { $0.title == "Client: hooks" })
        #expect(outdated.level == .warning && outdated.detail == "outdated. Run: brainmerge brain wire")
        #expect(!doctor(e).run().contains { $0.title.hasSuffix(": hook") })
    }

    /// A Claude Code folder that is gone says what to do about it, on the command line and in a sentence for a person.
    @Test func aMissingClaudeCodeFolderSaysWhatToDo() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let work = e.home.paths.cliProfile(slug: "work", isPrimary: false)
        try FileManager.default.removeItem(at: work)
        try FileManager.default.removeItem(at: e.primaryProfile.directory)
        let findings = doctor(e).run()
        let secondary = try #require(findings.first { $0.title == "Work: profile" })
        #expect(secondary.level == .error)
        #expect(secondary.detail == "Missing \(work.path). Put the folder back and run: brainmerge brain wire, or remove the account: brainmerge identity remove work")
        #expect(secondary.plain == "The Claude Code folder of Work is missing from ~/.claude-work. Put it back, or remove the account.")
        let primary = try #require(findings.first { $0.title == "Perso: profile" })
        #expect(primary.detail == "Missing \(e.primaryProfile.directory.path). Start Claude Code once to make it again, then run: brainmerge brain wire")
        #expect(primary.plain == "The Claude Code folder of Perso is missing from ~/.claude. Start Claude Code once to make it again.")
    }

    /// A project whose link still points into a memory Brainmerge no longer knows (an older `brain init` moved the default
    /// memory without its links): the notes written there are never saved, so it is said, with where and what to do.
    @Test func aLinkIntoAMemoryBrainmergeNoLongerKnowsIsSaid() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let moved = try Brain.initialize(at: e.home.url.appending(path: "Brain2"), language: .en)
        var state = try e.store.load(); state.brainPath = moved.root.path; try e.store.save(state)
        let finding = try #require(doctor(e).run().first { $0.title == "Perso: memory atelier" })
        #expect(finding.level == .warning)
        #expect(finding.detail.contains(e.brain.root.path) && finding.detail.contains("Run: brainmerge brain add"), "\(finding.detail)")
        #expect(finding.plain == "The notes of atelier for Perso go to ~/Brain, a memory Brainmerge no longer knows: they are not saved.")

        // Any other folder a project keeps its notes in is still left as it is.
        let own = e.home.url.appending(path: "elsewhere/notes")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: own)
        #expect(doctor(e).run().first { $0.title == "Perso: memory atelier" }?.level == .ok)
    }

    @Test func reportsMissingClaudeAndBrain() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        try FileManager.default.removeItem(at: e.claude.url)
        try FileManager.default.removeItem(at: e.brain.root)
        let findings = doctor(e).run()
        #expect(findings.contains { $0.title == "Claude.app" && $0.level == .error })
        #expect(findings.contains { $0.title == "Memory: Shared" && $0.level == .error })
    }

    @Test func checksThePrimarysOwnApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(!doctor(e).run().contains { $0.title == "Perso: own app" })   // switched off: nothing to check
        _ = try e.manager.update(slug: "perso", name: nil, tint: nil, logo: nil, ownApp: true)
        let app = e.home.paths.launcherApp(name: "Perso")
        #expect(doctor(e).run().contains { $0.title == "Perso: own app" && $0.level == .ok && $0.detail == app.path })

        // It opens another Claude than the one installed: rebuilding it points it back.
        try JSONEncoder().encode(LauncherConfig(openApp: "/Applications/Other.app"))
            .write(to: app.appending(path: "Contents/Resources/brainmerge.json"), options: .atomic)
        let moved = doctor(e).run().first { $0.title == "Perso: own app" }
        #expect(moved?.level == .warning)
        #expect(moved?.detail.contains("brainmerge identity rebuild perso") == true)

        try FileManager.default.removeItem(at: app)
        let missing = doctor(e).run().first { $0.title == "Perso: own app" }
        #expect(missing?.level == .error)
        #expect(missing?.detail == "Missing \(app.path). Run: brainmerge identity rebuild perso")
    }

    /// A launcher starts the Claude it was built for: once Claude moved (or another one was chosen), it starts the old
    /// one, or nothing when that one is gone. That is never "in place".
    @Test func aLauncherPinnedToAnotherClaudeIsNotInPlace() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let config = e.home.paths.launcherApp(name: "Client").appending(path: "Contents/Resources/brainmerge.json")
        #expect(doctor(e).run().first { $0.title == "Client: launcher" }?.level == .ok)

        let old = e.home.url.appending(path: "Old/Claude.app/Contents/MacOS/Claude").path
        try JSONEncoder().encode(LauncherConfig(configDir: "/c", dataDir: "/d", claudeExecutable: old)).write(to: config, options: .atomic)
        let moved = try #require(doctor(e).run().first { $0.title == "Client: launcher" })
        #expect(moved.level == .warning)
        #expect(moved.fix == .rebuild(slug: "client"))
        #expect(moved.detail.contains(old) && moved.detail.contains("Run: brainmerge identity rebuild client"), "\(moved.detail)")
        #expect(!moved.plain.contains("brainmerge"), "\(moved.plain)")

        try Data("{}".utf8).write(to: config, options: .atomic)
        #expect(doctor(e).run().first { $0.title == "Client: launcher" }?.fix == .rebuild(slug: "client"))
    }

    /// A copy of Claude made by hand that opens an account with an older Claude than the one installed (the owner's
    /// "Claude Second"): one warning per copy, which says what to do and never touches the copy.
    @Test func warnsWhenAHandMadeCopyRunsAnOlderClaude() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let data = e.home.url.appending(path: "Library/Application Support/Claude-Second")
        let profile = e.home.url.appending(path: ".claude-second")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        _ = try CLIProfile.create(at: profile, inheritingFrom: nil)
        var request = IdentityManager.AddRequest(name: "Agency")
        request.adoptDesktopData = data; request.adoptCLIProfile = profile
        _ = try e.manager.add(request)
        let apps = e.home.url.appending(path: "Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        #expect(!doctor(e).run().contains { $0.title.hasPrefix("Agency: Claude Second") })

        let copy = try HandMadeApp.make("Claude Second", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13")
        try HandMadeApp.make("Claude Second (ancienne 1.49585)", in: apps, script: HandMadeApp.ownersScript, version: "1.49585.0")
        // Up to date with the Claude installed (2.7032.0 here): nothing to warn about.
        try HandMadeApp.make("Claude Second (current)", in: apps, script: HandMadeApp.ownersScript, version: "2.7032.0")

        let findings = doctor(e).run()
        let warnings = findings.filter { $0.title.hasPrefix("Agency: Claude Second") }
        #expect(warnings.map(\.title) == ["Agency: Claude Second", "Agency: Claude Second (ancienne 1.49585)"])
        #expect(warnings.allSatisfy { $0.level == .warning })
        #expect(warnings.first?.detail == "A copy of Claude 2.2553.13 made by hand, \(copy.path), also opens this account, and Claude 2.7032.0 is installed: an older Claude on the same data can damage it. Use Brainmerge's app for this account, and move the copy to the Trash yourself once Agency is closed.")
        #expect(!findings.hasErrors)
        // The copies are only read.
        #expect(FileManager.default.fileExists(atPath: copy.path))
        for finding in findings {
            #expect(!finding.detail.contains("\u{2014}") && !finding.detail.contains("\u{2013}"))
        }
    }

    /// A setup with something wrong everywhere a button can mend it.
    func brokenEverywhere(_ e: ManagerEnv) throws -> [Doctor.Finding] {
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.update(slug: "perso", name: nil, tint: nil, logo: nil, ownApp: true)
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        try FileManager.default.removeItem(at: work.url)
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Client"))
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Perso"))
        try HookInstaller.remove(settingsFile: e.primaryProfile.settingsFile)
        try Data("# sans bloc\n".utf8).write(to: CLIProfile(directory: client.cliProfile(in: e.home.paths)).claudeMD)
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: e.home.url.appending(path: "gone"))
        let missing = GitAvailability(shell: Shell { _, _, _, _ in ShellResult(status: 2, stdout: "", stderr: "") }, isExecutable: { _ in false })
        return Doctor(paths: e.home.paths, store: e.store, claudeAppURL: e.claude.url, cliPath: e.cliPath, git: missing).run()
    }

    /// Each finding the app can mend names the one button that mends it; the others, and every finding that is fine, none.
    @Test func eachFindingNamesItsFix() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let findings = try brokenEverywhere(e)
        func fix(_ title: String) -> Doctor.Fix?? { findings.first { $0.title == title }.map(\.fix) }
        #expect(fix("git") == .some(.installAppleTools))
        #expect(fix("Command line") == .some(.installCLI))
        #expect(fix("Perso: hooks") == .some(.repairHooks))
        #expect(fix("Client: CLAUDE.md") == .some(.repairLinks(brainID: "shared")))
        #expect(fix("Perso: memory atelier") == .some(.repairLinks(brainID: "shared")))
        #expect(fix("Client: launcher") == .some(.rebuild(slug: "client")))
        #expect(fix("Perso: own app") == .some(.rebuild(slug: "perso")))
        #expect(fix("Memory: Work") == .some(.chooseMemory(brainID: "work")))
        #expect(fix("Claude.app") == .some(nil))
        #expect(fix("Client: login") == .some(nil))
        #expect(findings.filter { $0.level == .ok }.allSatisfy { $0.fix == nil })

        let current = findings.first { $0.title == "Client: hooks" }
        #expect(current?.level == .ok && current?.fix == nil)

        // No memory at all: choosing its folder is the fix.
        let bare = try ManagerEnv.make(withBrain: false); defer { bare.home.remove() }
        let none = doctor(bare).run().first { $0.title == "Memory" }
        #expect(none?.fix == .chooseMemory(brainID: AppState.defaultBrainID))
    }

    /// The app shows `plain`: a sentence for a person, never a command to type. The command line keeps its "Run: …".
    @Test func plainSentencesNeverNameACommand() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        var findings = try brokenEverywhere(e)
        let bare = try ManagerEnv.make(withBrain: false); defer { bare.home.remove() }
        findings += doctor(bare).run()
        try FileManager.default.removeItem(at: bare.claude.url)
        findings += doctor(bare).run()
        #expect(findings.contains { $0.detail.contains("Run: brainmerge ") })
        for finding in findings {
            #expect(!finding.plain.isEmpty, "\(finding.title)")
            #expect(!finding.plain.contains("brainmerge ") && !finding.plain.contains("Run:"), "\(finding.title): \(finding.plain)")
            #expect(!finding.plain.contains("\u{2014}") && !finding.plain.contains("\u{2013}"), "\(finding.title)")
        }
        #expect(findings.first { $0.title == "Perso: hooks" }?.plain == "The hooks of Perso are missing: its memory is not saved when a turn ends.")
        #expect(findings.first { $0.title == "Memory: Work" }?.plain == "The memory Work is missing from ~/Brain-work.")
    }

    @Test func everyMemoryIsChecked() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        var request = IdentityManager.AddRequest(name: "Client"); request.brain = "work"
        _ = try e.manager.add(request)
        let findings = doctor(e).run()
        #expect(findings.contains { $0.title == "Memory: Shared" && $0.level == .ok })
        #expect(findings.contains { $0.title == "Memory: Work" && $0.level == .ok && $0.detail.contains(work.path) })
        #expect(findings.contains { $0.title == "Client: CLAUDE.md" && $0.level == .ok })
        try FileManager.default.removeItem(at: work.url)
        let broken = doctor(e).run()
        let finding = broken.first { $0.title == "Memory: Work" }
        #expect(finding?.level == .error)
        // Never "brain init" for a memory that is not the default one: that command moves the default memory.
        #expect(finding?.detail.contains("brain init") == false)
        #expect(finding?.detail.contains("brain forget work") == true)
    }
}
