import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct TerminalCommandsTests {
    func model(_ e: ManagerEnv, cli: URL) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.commandLine = { cli }
        return model
    }

    func embeddedCLI(in e: ManagerEnv) throws -> URL {
        let cli = e.home.url.appending(path: "Brainmerge.app/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: cli)
        return cli
    }

    @Test func offByDefaultInAnOlderState() throws {
        let state = try JSONDecoder().decode(AppState.self, from: Data(#"{"schemaVersion": 2, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#.utf8))
        #expect(!state.terminalCommands)
    }

    @Test func theCopiedCommandFollowsTheSwitch() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        #expect(m.terminalCommand(for: "work") == "brainmerge code work")
        await m.setTerminalCommands(true).value
        #expect(m.terminalCommand(for: "work") == "claude-work")
    }

    /// The switch is on but claude-work is someone else's program: the card copies the command that is surely ours.
    @Test func aCommandThatIsNotOursIsNeverCopied() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try FileManager.default.createDirectory(at: e.home.paths.localBin, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: CLIInstaller.accountLink(in: e.home.paths, slug: "work"))
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        await m.setTerminalCommands(true).value
        #expect(m.terminalCommand(for: "ruben") == "claude-ruben")
        #expect(m.terminalCommand(for: "work") == "brainmerge code work")
    }

    @Test func theSwitchMakesAndRemovesEachAccountsLink() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        let fm = FileManager.default
        func linked(_ slug: String) -> Bool {
            (try? fm.destinationOfSymbolicLink(atPath: CLIInstaller.accountLink(in: e.home.paths, slug: slug).path)) != nil
        }
        await m.setTerminalCommands(true).value
        #expect(linked("ruben") && linked("work"))
        #expect(try e.store.load().terminalCommands)
        await m.setTerminalCommands(false).value
        #expect(!linked("ruben") && !linked("work"))
    }
}
