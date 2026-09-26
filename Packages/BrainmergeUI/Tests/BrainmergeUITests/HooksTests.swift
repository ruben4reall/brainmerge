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

    /// A Stop hook as Brainmerge 0.5 wrote it: unguarded, so a trashed app shows a hook error on every turn.
    func oldHooks(_ e: ManagerEnv) -> String {
        #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"},{"type":"command","command":"\"\#(e.cliPath)\" sync --identity perso"}]}]}}"#
    }

    /// An update over an older Brainmerge: the next launch brings every account's hooks up to date where they stand, with
    /// no click, and keeps the person's own. Hooks that are already current are not written again.
    @Test func aLaunchUpgradesHooksAnOlderBrainmergeWrote() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let settings = e.primaryProfile.settingsFile
        try Data(oldHooks(e).utf8).write(to: settings)
        #expect(HookInstaller.health(settingsFile: settings, cliPath: e.cliPath, slug: "perso") == .outdated)
        try Data(".DS_Store\n.brainmerge/lock\n".utf8).write(to: e.brain.gitignore)

        await model(e).launch(minimum: .zero)
        #expect(HookInstaller.health(settingsFile: settings, cliPath: e.cliPath, slug: "perso") == .current)
        #expect(try HookInstaller.isInstalled(settingsFile: settings, event: .sessionStart))
        #expect(try HookInstaller.isInstalled(settingsFile: settings, event: .postToolUse))
        // What each account notes it wrote stays out of an older memory's history from the first launch.
        #expect(try String(contentsOf: e.brain.gitignore, encoding: .utf8).hasSuffix(".brainmerge/touched/\n"))
        #expect(try String(contentsOf: settings, encoding: .utf8).contains("say done"))

        let written = try Data(contentsOf: settings)
        let stamp = try FileManager.default.attributesOfItem(atPath: settings.path)[.modificationDate] as? Date
        await model(e).launch(minimum: .zero)
        #expect(try Data(contentsOf: settings) == written)
        #expect(try FileManager.default.attributesOfItem(atPath: settings.path)[.modificationDate] as? Date == stamp)
    }

    /// The SessionStart hook writes the memory's list of projects under the memory's lock. The minute pass takes the same
    /// lock: while a hook holds it, the pass skips its turn instead of writing over the hook's change, and the next one links.
    @Test func theMinutePassSkipsWhileAHookHoldsTheMemoryLock() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let folder = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.home.url.path + "/kayak"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appending(path: "memory")
        let m = model(e)
        let fd = open(e.brain.lockFile.path, O_CREAT | O_RDWR, 0o644)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        m.wireNewProjects()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        flock(fd, LOCK_UN)
        m.wireNewProjects()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "kayak").path)
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
        let settings = e.primaryProfile.settingsFile
        try Data(oldHooks(e).utf8).write(to: settings)
        for environment in [["BRAINMERGE_CAPTURE": "1"], ["BRAINMERGE_HOME": e.home.url.path]] {
            let m = model(e)
            m.environment = environment
            let cli = try embeddedCLI(e)
            m.commandLine = { cli }
            await m.launch(minimum: .zero)
            #expect(linkDestination(e) == nil, "\(environment)")
            #expect(try String(contentsOf: settings, encoding: .utf8) == oldHooks(e), "\(environment)")
            await m.refreshHooks()
            #expect(m.hooks == nil, "\(environment)")
        }
    }
}
