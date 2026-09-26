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

    func linked(_ e: ManagerEnv, _ slug: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.accountLink(in: e.home.paths, slug: slug).path)) != nil
    }

    func switchOn(_ e: ManagerEnv) throws {
        var state = try e.store.load()
        state.terminalCommands = true
        try e.store.save(state)
    }

    /// After a relaunch the switch shows what state.json holds, not its default.
    @Test func theSwitchShowsOnAfterARelaunch() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        try switchOn(e)
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        #expect(m.terminalCommands)
    }

    /// Accounts added from the command line while the app was closed get their command at the next launch.
    @Test func aLaunchLinksAnAccountThatHasNoLinkYet() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try switchOn(e)
        #expect(!linked(e, "work"))
        let m = model(e, cli: try embeddedCLI(in: e))
        await m.launch(minimum: .zero)
        #expect(linked(e, "ruben") && linked(e, "work"))
    }

    /// Added in the app while the brainmerge link points elsewhere (or is missing): linked to the app's own command line.
    @Test func addingInTheAppLinksTheNewAccount() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        await m.setTerminalCommands(true).value
        var form = AddAccountForm(); form.name = "Work"
        #expect(await m.add(form, open: false))
        #expect(linked(e, "work"))
    }

    @Test func theSwitchMakesAndRemovesEachAccountsLink() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let m = model(e, cli: try embeddedCLI(in: e))
        m.reload()
        await m.setTerminalCommands(true).value
        #expect(linked(e, "ruben") && linked(e, "work"))
        #expect(try e.store.load().terminalCommands)
        await m.setTerminalCommands(false).value
        #expect(!linked(e, "ruben") && !linked(e, "work"))
    }
}
