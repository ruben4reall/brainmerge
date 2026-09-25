import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// Settings > Command line says whether every account's hooks are current, "Repair hooks" writes them again, and each
/// launch points the command line link they call at this copy when the Brainmerge it pointed at is gone.
@MainActor @Suite struct HooksTests {
    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        return model
    }

    /// The command line inside an app bundle of the temporary home, like the one the release embeds.
    func embeddedCLI(_ e: ManagerEnv, app: String = "Applications/Brainmerge.app") throws -> URL {
        let cli = e.home.url.appending(path: "\(app)/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }

    func linkDestination(_ e: ManagerEnv) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.link(in: e.home.paths).path)
    }

    @Test func theSentenceSaysCurrentMissingOrGone() {
        #expect(HooksSummary(states: [.current, .current, .current], commandLinePresent: true).sentence == "Hooks: 3 accounts, all current.")
        #expect(HooksSummary(states: [.current], commandLinePresent: true).sentence == "Hooks: 1 account, current.")
        #expect(HooksSummary(states: [.current, .outdated], commandLinePresent: false).sentence
            == "Some hooks point to a Brainmerge that is no longer there.")
        #expect(HooksSummary(states: [.current, .current], commandLinePresent: false).sentence
            == "Some hooks point to a Brainmerge that is no longer there.")
        #expect(HooksSummary(states: [.current, .outdated], commandLinePresent: true).sentence == "Some hooks are missing or out of date.")
        #expect(HooksSummary(states: [.missing, .missing], commandLinePresent: false).sentence == "Some hooks are missing or out of date.")
        #expect(HooksSummary(states: [], commandLinePresent: true).sentence == nil)
        #expect(HooksSummary(states: [.current, .current], commandLinePresent: true).allCurrent)
        #expect(!HooksSummary(states: [.current], commandLinePresent: false).allCurrent)
        #expect(!HooksSummary(states: [], commandLinePresent: true).allCurrent)
    }

    @Test func settingsReadsEachAccountsHooksAndRepairsThem() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        var request = IdentityManager.AddRequest(name: "Client")
        request.surfaces = Surfaces(desktop: false, cli: true)
        let client = try e.manager.add(request)
        let m = model(e)
        let cli = try embeddedCLI(e)
        m.commandLine = { cli }
        #expect(m.hooks == nil)
        await m.refreshHooks()
        // Nothing at ~/.local/bin/brainmerge yet: every hook would find nothing to run.
        #expect(m.hooks?.sentence == "Some hooks point to a Brainmerge that is no longer there.")

        let settings = CLIProfile(directory: client.cliProfile(in: e.home.paths)).settingsFile
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8).write(to: settings)
        await m.repairHooks()
        #expect(linkDestination(e) == cli.resolvingSymlinksInPath().path)
        #expect(m.hooks?.sentence == "Hooks: 2 accounts, all current.")
        #expect(m.hooks?.allCurrent == true)
        #expect(HookInstaller.health(settingsFile: settings, cliPath: e.cliPath, slug: "client") == .current)
        #expect(try String(contentsOf: settings, encoding: .utf8).contains("say done"))
        #expect(m.message == nil)

        try HookInstaller.remove(settingsFile: settings)
        await m.refreshHooks()
        #expect(m.hooks?.sentence == "Some hooks are missing or out of date.")
    }

    /// A repair from a copy on a read-only disk says why the link cannot be made, instead of looking done.
    @Test func repairFromADiskImageSaysWhy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        m.commandLine = { URL(fileURLWithPath: "/bin/ls") }
        await m.repairHooks()
        #expect(m.message?.detail.contains("read-only") == true || m.message?.title.contains("read-only") == true)
        #expect(linkDestination(e) == nil)
    }

    /// The app was moved or trashed: at the next launch, the link its hooks call points at the copy that runs now.
    @Test func eachLaunchRepointsALinkToAGoneBrainmerge() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let link = CLIInstaller.link(in: e.home.paths)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: e.home.url.appending(path: "Downloads/Brainmerge.app/Contents/MacOS/brainmerge-cli").path)
        let m = model(e)
        let cli = try embeddedCLI(e)
        m.commandLine = { cli }
        await m.launch(minimum: .zero)
        #expect(linkDestination(e) == cli.resolvingSymlinksInPath().path)
    }

    /// Before the guided setup (no account yet), a launch links nothing: the setup asks first.
    @Test func aLaunchBeforeSetupLinksNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        let cli = try embeddedCLI(e)
        m.commandLine = { cli }
        await m.launch(minimum: .zero)
        #expect(linkDestination(e) == nil)
        #expect(!FileManager.default.fileExists(atPath: CLIInstaller.link(in: e.home.paths).path))
    }

    /// A capture or a demo runs on a demo home whose hooks call nothing real: no hooks row, and no link mended at launch.
    @Test func capturesAndDemosLeaveHooksAlone() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        for environment in [["BRAINMERGE_CAPTURE": "1"], ["BRAINMERGE_HOME": e.home.url.path]] {
            let m = model(e)
            m.environment = environment
            let cli = try embeddedCLI(e)
            m.commandLine = { cli }
            await m.launch(minimum: .zero)
            #expect(linkDestination(e) == nil, "\(environment)")
            await m.refreshHooks()
            #expect(m.hooks == nil, "\(environment)")
        }
    }
}
