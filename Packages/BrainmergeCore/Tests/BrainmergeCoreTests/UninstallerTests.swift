import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct UninstallerTests {
    func uninstaller(_ e: ManagerEnv, manager: IdentityManager? = nil) -> Uninstaller {
        Uninstaller(paths: e.home.paths, store: e.store, manager: manager ?? e.manager)
    }

    @Test func linksBecomeRealFoldersAndNothingOfTheirsIsDeleted() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let fm = FileManager.default
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let notes = e.brain.memoryDir(forProject: "atelier")
        try Data("# pricing\n".utf8).write(to: notes.appending(path: "decision_pricing.md"))
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        try fm.createDirectory(at: e.home.paths.localBin, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: e.home.paths.localBin.appending(path: "brainmerge"),
                                  withDestinationURL: e.home.url.appending(path: "Applications/Brainmerge.app/Contents/MacOS/brainmerge-cli"))

        let plan = try uninstaller(e).plan()
        #expect(plan.removed.contains { $0.contains("2 Claude Code profiles") })
        #expect(plan.kept.contains { $0.contains(e.brain.root.path) })
        let report = try uninstaller(e).run()
        #expect(report.detachedAccounts == 2 && report.copiedMemories == 1 && report.removedLaunchers == 1)

        // The project's memory is a real folder now, with the note; the brain still has it too.
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(try String(contentsOf: link.appending(path: "decision_pricing.md"), encoding: .utf8) == "# pricing\n")
        #expect(fm.fileExists(atPath: notes.appending(path: "decision_pricing.md").path))
        // Hooks and blocks are gone; profiles, data folders and the brain stay.
        #expect(!(try HookInstaller.isInstalled(settingsFile: e.primaryProfile.settingsFile)))
        #expect(!ManagedBlock.contains(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)))
        #expect(fm.fileExists(atPath: client.cliProfile(in: e.home.paths).path))
        #expect(fm.fileExists(atPath: client.desktopData(in: e.home.paths).path))
        #expect(fm.fileExists(atPath: e.brain.brainMD.path))
        // Launchers, the command line link and Brainmerge's own folders are gone.
        #expect(!fm.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: e.home.paths.localBin.appending(path: "brainmerge").path)) == nil)
        #expect(!fm.fileExists(atPath: e.home.paths.appSupport.path))
        #expect(!fm.fileExists(atPath: e.home.paths.stateFile.path))
    }

    @Test func refusesWhileAnAccountIsOpen() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let running = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false,
                                      monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        #expect(throws: BrainmergeError.identityRunning("client")) { try uninstaller(e, manager: running).run() }
        #expect(FileManager.default.fileExists(atPath: e.home.paths.stateFile.path))
        #expect(try HookInstaller.isInstalled(settingsFile: e.primaryProfile.settingsFile))
    }

    @Test func aBrokenLinkGoesAndAMissingProfileIsSkipped() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let fm = FileManager.default
        _ = try e.manager.adoptPrimary(name: "Perso")
        // A link into the memory whose target is gone (the memory moved): removed. A broken link of the person's own: left alone.
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: e.brain.memoryDir(forProject: "gone"))
        let foreign = e.primaryProfile.projectsDir.appending(path: "-Users-r-elsewhere", directoryHint: .isDirectory).appending(path: "memory")
        try fm.createDirectory(at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: foreign, withDestinationURL: e.home.url.appending(path: "gone"))
        var state = try e.store.load()
        state.identities.append(Identity(slug: "ghost", name: "Ghost"))   // no profile on disk
        try e.store.save(state)
        let report = try uninstaller(e).run()
        #expect(report.copiedMemories == 0)
        #expect(!fm.fileExists(atPath: link.path) && (try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect((try? fm.destinationOfSymbolicLink(atPath: foreign.path)) == e.home.url.appending(path: "gone").path)
        #expect(!fm.fileExists(atPath: e.home.paths.appSupport.path))
    }

    @Test func linksMadeByThePersonAndAForeignCommandLineLinkSurvive() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let fm = FileManager.default
        _ = try e.manager.adoptPrimary(name: "Perso")
        // The person linked a project's memory to a folder of their own: Brainmerge never made it, it stays.
        let own = e.home.url.appending(path: "my-notes", directoryHint: .isDirectory)
        try fm.createDirectory(at: own, withIntermediateDirectories: true)
        try Data("mine\n".utf8).write(to: own.appending(path: "note.md"))
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: own)
        // A brainmerge link in ~/.local/bin that is not ours stays too.
        try fm.createDirectory(at: e.home.paths.localBin, withIntermediateDirectories: true)
        let foreign = e.home.paths.localBin.appending(path: "brainmerge")
        try fm.createSymbolicLink(at: foreign, withDestinationURL: e.home.url.appending(path: "somewhere-else/brainmerge"))

        let plan = try uninstaller(e).plan()
        #expect(!plan.removed.contains { $0.contains("command line link") })
        let report = try uninstaller(e).run()
        #expect(report.copiedMemories == 0)
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == own.path)
        #expect(try fm.destinationOfSymbolicLink(atPath: foreign.path) == e.home.url.appending(path: "somewhere-else/brainmerge").path)
    }

    /// The primary's own app is Brainmerge's and goes, even while Claude runs; Claude and an app the person made stay.
    @Test func thePrimarysOwnAppGoesAndThePersonsAppsStay() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let fm = FileManager.default
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.update(slug: "perso", name: nil, tint: nil, logo: nil, ownApp: true)
        let opener = e.home.paths.launcherApp(name: "Perso")
        #expect(fm.fileExists(atPath: opener.path))
        let personsApp = e.home.url.appending(path: "Applications/Claude Perso.app", directoryHint: .isDirectory)
        try fm.createDirectory(at: personsApp.appending(path: "Contents"), withIntermediateDirectories: true)
        let exe = e.claude.executable.path
        let claudeOpen = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                         claudeAppURL: e.claude.url, registerLaunchers: false,
                                         monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe)\n" }))

        #expect(try uninstaller(e, manager: claudeOpen).plan().removed.contains { $0.contains("1 account app in") })
        let report = try uninstaller(e, manager: claudeOpen).run()
        #expect(report.removedLaunchers == 1)
        #expect(!fm.fileExists(atPath: opener.path))
        #expect(fm.fileExists(atPath: personsApp.path))
        #expect(fm.fileExists(atPath: e.claude.executable.path))
    }
}
