import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct IdentityManagerTests {
    @Test func adoptsPrimaryWithoutTouchingItsFiles() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let identity = try e.manager.adoptPrimary(name: "Perso")
        #expect(identity.isPrimary && identity.slug == "perso")
        let claudeMD = try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)
        #expect(claudeMD.hasPrefix("# Mes règles\n\n- pas de tiret cadratin\n"))
        #expect(ManagedBlock.contains(claudeMD))
        #expect(try HookInstaller.isInstalled(settingsFile: e.primaryProfile.settingsFile))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: e.primaryProfile.settingsFile)) as! [String: Any]
        #expect(HookInstaller.stopCommands(root).first == "cd vault && git push")
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "atelier").path)
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["perso"]?.name == "Perso")
        #expect(try e.store.load().primary?.slug == "perso")
        #expect(try e.manager.adoptPrimary(name: "Autre").slug == "perso")
    }

    @Test func addsLauncherIdentityWithProfileDataDirAndApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        var request = IdentityManager.AddRequest(name: "ClientStudio")
        request.tint = .blue
        let identity = try e.manager.add(request)
        #expect(identity.slug == "clientstudio")
        let profile = CLIProfile(directory: identity.cliProfile(in: e.home.paths))
        #expect(profile.directory.lastPathComponent == ".claude-clientstudio")
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: profile.settingsFile)) as! [String: Any]
        #expect(settings["language"] as? String == "french")
        #expect(HookInstaller.stopCommands(settings).count == 1)
        #expect(ManagedBlock.contains(try String(contentsOf: profile.claudeMD, encoding: .utf8)))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: profile.skillsDir.path) == e.primaryProfile.skillsDir.path)
        #expect(FileManager.default.fileExists(atPath: identity.desktopData(in: e.home.paths).path))
        let app = e.home.paths.launcherApp(name: "ClientStudio")
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/Resources/icon.icns").path))
        #expect(try e.store.load().identity(slug: "clientstudio")?.builtForClaudeVersion == "2.7032.0")
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["clientstudio"]?.tint == "blue")
        #expect(throws: BrainmergeError.identityNameTaken("ClientStudio")) { try e.manager.add(IdentityManager.AddRequest(name: "ClientStudio")) }
    }

    @Test func sharedHistoryLinksProjectsToPrimary() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        var request = IdentityManager.AddRequest(name: "Client")
        request.sharedHistory = true
        let identity = try e.manager.add(request)
        let projects = CLIProfile(directory: identity.cliProfile(in: e.home.paths)).projectsDir
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: projects.path) == e.primaryProfile.projectsDir.path)
    }

    @Test func adoptsExistingProfileAndDataDir() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let cli = e.home.url.appending(path: ".claude-second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try Data(#"{"model":"sonnet"}"#.utf8).write(to: cli.appending(path: "settings.json"))
        let data = e.home.url.appending(path: "Library/Application Support/Claude-Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("cookie".utf8).write(to: data.appending(path: "Cookies"))
        var request = IdentityManager.AddRequest(name: "Client")
        request.adoptCLIProfile = cli
        request.adoptDesktopData = data
        let identity = try e.manager.add(request)
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: cli.appending(path: "settings.json"))) as! [String: Any]
        #expect(settings["model"] as? String == "sonnet")
        #expect(HookInstaller.stopCommands(settings).count == 1)
        #expect(FileManager.default.fileExists(atPath: data.appending(path: "Cookies").path))
        let config = try JSONDecoder().decode(LauncherConfig.self, from: Data(contentsOf:
            e.home.paths.launcherApp(name: "Client").appending(path: "Contents/Resources/brainmerge.json")))
        #expect(config.configDir == cli.path && config.dataDir == data.path)
        #expect(identity.cliProfilePath == cli.path)
    }

    @Test func updatesNameTintAndRebuildsLauncher() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let updated = try e.manager.update(slug: "client", name: "ClientStudio", tint: .green, logo: nil, note: "Institut")
        #expect(updated.name == "ClientStudio" && updated.tint == .green && updated.slug == "client")
        #expect(updated.note == "Institut")
        #expect(FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "ClientStudio").path))
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        let claudeMD = try String(contentsOf: CLIProfile(directory: updated.cliProfile(in: e.home.paths)).claudeMD, encoding: .utf8)
        #expect(claudeMD.contains("identity \"ClientStudio\""))
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["client"] == IdentityRegistry.Entry(name: "ClientStudio", tint: "green"))
    }

    @Test func removeDeletesSecondaryAndOnlyDetachesPrimary() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let identity = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try e.manager.remove(slug: "client", deleteData: true)
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        #expect(!FileManager.default.fileExists(atPath: identity.cliProfile(in: e.home.paths).path))
        #expect(!FileManager.default.fileExists(atPath: identity.desktopData(in: e.home.paths).path))
        #expect(try e.store.load().identity(slug: "client") == nil)

        try e.manager.remove(slug: "perso", deleteData: true)
        #expect(FileManager.default.fileExists(atPath: e.primaryProfile.claudeMD.path))
        #expect(!ManagedBlock.contains(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)))
        #expect(try !HookInstaller.isInstalled(settingsFile: e.primaryProfile.settingsFile))
        #expect(try e.store.load().identities.isEmpty)
    }

    @Test func addWithoutBrainCreatesNothing() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        #expect(throws: BrainmergeError.brainNotConfigured) { try e.manager.add(IdentityManager.AddRequest(name: "Client")) }
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.cliProfile(slug: "client", isPrimary: false).path))
        #expect(try e.store.load().identities.isEmpty)
    }

    @Test func rebuildFollowsClaudeVersion() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        var plist = try Plist.read(e.claude.infoPlist)
        plist["CFBundleShortVersionString"] = "2.8000.0"
        try Plist.write(plist, to: e.claude.infoPlist)
        try e.manager.rebuild(slug: "client")
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.8000.0")
        #expect(throws: BrainmergeError.identityNotFound("nope")) { try e.manager.rebuild(slug: "nope") }
        #expect(throws: BrainmergeError.identityNotFound("nope")) { try e.manager.launch(slug: "nope") }
    }

    @Test func duplicateNamesAreRefusedCaseInsensitively() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        #expect(throws: BrainmergeError.identityNameTaken("client")) { try e.manager.add(IdentityManager.AddRequest(name: "client")) }
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        #expect(throws: BrainmergeError.identityNameTaken("PERSO")) { try e.manager.update(slug: "work", name: "PERSO", tint: nil, logo: nil) }
        #expect(try e.store.load().identities.count == 3)
    }

    @Test func refusesRebuildEditAndRemoveWhileRunning() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let dataDir = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let running = ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(dataDir)\n" })
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: running)
        #expect(try manager.isRunning(client))
        #expect(throws: BrainmergeError.identityRunning("client")) { try manager.rebuild(slug: "client") }
        #expect(throws: BrainmergeError.identityRunning("client")) { try manager.update(slug: "client", name: "Autre", tint: nil, logo: nil) }
        #expect(throws: BrainmergeError.identityRunning("client")) { try manager.remove(slug: "client", deleteData: false) }
        #expect(FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
    }

    @Test func removeNeverDeletesAdoptedFolders() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let cli = e.home.url.appending(path: ".claude-second", directoryHint: .isDirectory)
        let data = e.home.url.appending(path: "Library/Application Support/Claude-Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        var request = IdentityManager.AddRequest(name: "Client")
        request.adoptCLIProfile = cli
        request.adoptDesktopData = data
        _ = try e.manager.add(request)
        try e.manager.remove(slug: "client", deleteData: true)
        #expect(FileManager.default.fileExists(atPath: cli.path))
        #expect(FileManager.default.fileExists(atPath: data.path))
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
    }

    @Test func writesThroughSymlinkedSettingsAndClaudeMD() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let dotfiles = e.home.url.appending(path: "dotfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        for name in ["settings.json", "CLAUDE.md"] {
            let original = e.primaryProfile.directory.appending(path: name)
            let target = dotfiles.appending(path: name)
            try FileManager.default.moveItem(at: original, to: target)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
        }
        _ = try e.manager.adoptPrimary(name: "Perso")
        for name in ["settings.json", "CLAUDE.md"] {
            let link = e.primaryProfile.directory.appending(path: name)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == dotfiles.appending(path: name).path)
        }
        #expect(try String(contentsOf: dotfiles.appending(path: "CLAUDE.md"), encoding: .utf8).contains(ManagedBlock.start))
        #expect(try HookInstaller.isInstalled(settingsFile: dotfiles.appending(path: "settings.json")))
    }

    // MARK: Several memories

    @Test func addsAMemoryAndAttachesAnAccountToIt() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        #expect(work.id == "work" && work.name == "Work")
        #expect(work.path == e.home.url.appending(path: "Brain-work").path)
        #expect(Brain(root: work.url).isInitialized)
        #expect(try e.store.load().brains.map(\.id) == ["shared", "work"])
        var request = IdentityManager.AddRequest(name: "Client")
        request.brain = "work"
        let client = try e.manager.add(request)
        #expect(client.brain == "work")
        let profile = CLIProfile(directory: client.cliProfile(in: e.home.paths))
        #expect(try String(contentsOf: profile.claudeMD, encoding: .utf8).contains(work.path))
        #expect(try IdentityRegistry.load(Brain(root: work.url).identitiesFile).identities["client"]?.name == "Client")
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["client"] == nil)
        #expect(throws: BrainmergeError.brainNameTaken("Work")) { try e.manager.addBrain(name: "work", path: nil, language: .en) }
        var unknown = IdentityManager.AddRequest(name: "Nope"); unknown.brain = "gone"
        #expect(throws: BrainmergeError.brainUnknown("gone")) { try e.manager.add(unknown) }
        #expect(try e.store.load().identity(slug: "nope") == nil)
    }

    @Test func switchingMemoryRelinksProjectsAndKeepsNotesWhereTheyWere() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        let sharedNotes = e.brain.memoryDir(forProject: "atelier")
        try Data("# pricing\n".utf8).write(to: sharedNotes.appending(path: "decision_pricing.md"))
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)

        try e.manager.setBrain(of: "perso", to: "work")

        let state = try e.store.load()
        #expect(state.identity(slug: "perso")?.brain == "work")
        #expect(state.brain(for: state.identity(slug: "perso")!)?.id == "work")
        let workNotes = Brain(root: work.url).memoryDir(forProject: "atelier")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == workNotes.path)
        // The note stays where it was written; the new memory starts from what it already holds.
        #expect(FileManager.default.fileExists(atPath: sharedNotes.appending(path: "decision_pricing.md").path))
        #expect(!FileManager.default.fileExists(atPath: workNotes.appending(path: "decision_pricing.md").path))
        let claudeMD = try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)
        #expect(claudeMD.contains(work.path) && !claudeMD.contains(e.brain.root.path + "\n"))
        // Back to the shared memory: the link comes back, the note is there again.
        try e.manager.setBrain(of: "perso", to: "shared")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == sharedNotes.path)
        #expect(throws: BrainmergeError.brainUnknown("gone")) { try e.manager.setBrain(of: "perso", to: "gone") }
        #expect(throws: BrainmergeError.identityNotFound("nobody")) { try e.manager.setBrain(of: "nobody", to: "work") }
    }

    @Test func forgettingAMemoryInUseIsRefusedAndTheFolderStays() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        try e.manager.setBrain(of: "perso", to: "work")
        #expect(throws: BrainmergeError.brainInUse("Work")) { try e.manager.forgetBrain(id: "work") }
        #expect(throws: BrainmergeError.brainIsDefault) { try e.manager.forgetBrain(id: "shared") }
        try e.manager.setBrain(of: "perso", to: "shared")
        try e.manager.forgetBrain(id: "work")
        #expect(try e.store.load().brains.map(\.id) == ["shared"])
        #expect(FileManager.default.fileExists(atPath: work.url.appending(path: "BRAIN.md").path))
        try e.manager.renameBrain(id: "shared", name: "Everyone")
        #expect(try e.store.load().brains.first?.name == "Everyone")
        #expect(try e.store.load().brains.first?.path == e.brain.root.path)
    }

    @Test func anAccountCanBeCreatedWithItsOwnMemory() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        var request = IdentityManager.AddRequest(name: "Work")
        request.ownBrain = true
        let identity = try e.manager.add(request)
        let state = try e.store.load()
        #expect(identity.brain == "work")
        #expect(state.brains.map(\.id) == ["shared", "work"])
        #expect(state.brain(for: identity)?.path == e.home.url.appending(path: "Brain-work").path)
        #expect(Brain(root: state.brain(for: identity)!.url).isInitialized)
        // The same name again: the account is refused before any memory is created.
        var again = IdentityManager.AddRequest(name: "Work"); again.ownBrain = true
        #expect(throws: BrainmergeError.identityNameTaken("Work")) { try e.manager.add(again) }
        #expect(try e.store.load().brains.count == 2)
    }

    @Test func switchingToADistinctIconBuildsTheTintedCopy() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let fm = FileManager.default
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        #expect(fm.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        let distinct = try e.manager.update(slug: "client", name: nil, tint: nil, logo: nil, iconMode: .tintedClone)
        #expect(distinct.iconMode == .tintedClone && distinct.builtForClaudeVersion == "2.7032.0")
        #expect(fm.fileExists(atPath: e.home.paths.tintedClone(name: "Client").path))
        #expect(!fm.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        #expect(try e.store.load().identity(slug: "client")?.appURL(in: e.home.paths) == e.home.paths.tintedClone(name: "Client"))
        let plain = try e.manager.update(slug: "client", name: nil, tint: nil, logo: nil, iconMode: .launcher)
        #expect(plain.iconMode == .launcher)
        #expect(fm.fileExists(atPath: e.home.paths.launcherApp(name: "Client").path))
        #expect(!fm.fileExists(atPath: e.home.paths.tintedClone(name: "Client").path))
        #expect(try e.store.load().primary?.appURL(in: e.home.paths) == nil)
    }

    @Test func aPhotoCanBeRemoved() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let photo = try FakeIcon.orangePNG(in: e.home.url)
        var request = IdentityManager.AddRequest(name: "Client"); request.logo = photo
        #expect(try e.manager.add(request).logoPath == photo.path)
        let cleared = try e.manager.update(slug: "client", name: nil, tint: .green, logo: nil, clearLogo: true)
        #expect(cleared.logoPath == nil && cleared.tint == .green)
        #expect(try e.store.load().identity(slug: "client")?.logoPath == nil)
    }

    @Test func memoryNamesAndFoldersAreValidated() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(throws: BrainmergeError.brainNameEmpty) { try e.manager.addBrain(name: "   ", path: nil, language: .en) }
        #expect(throws: BrainmergeError.brainFolderInUse(e.brain.root.path)) { try e.manager.addBrain(name: "Again", path: e.brain.root, language: .en) }
        #expect(throws: BrainmergeError.brainNameEmpty) { try e.manager.renameBrain(id: "shared", name: "") }
        #expect(try e.store.load().brains.count == 1)
    }

    // MARK: Swapping two names

    func launcherConfig(_ app: URL) throws -> LauncherConfig {
        try JSONDecoder().decode(LauncherConfig.self, from: Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json")))
    }

    func appsInLaunchersDir(_ e: ManagerEnv) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: e.home.paths.launchersDir.path)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
    }

    @Test func swappingNamesRenamesBothAccountsAndTheirApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let agency = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        try e.manager.swapNames("ruben", with: "agency")
        let state = try e.store.load()
        #expect(state.identity(slug: "ruben")?.name == "Agency")
        #expect(state.identity(slug: "agency")?.name == "Ruben")
        // The secondary's app carries its new name and still opens its own folders; no temporary app is left behind.
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Ruben")).dataDir == agency.desktopData(in: e.home.paths).path)
        // Claude's instructions and the memory's list of accounts follow.
        let primaryMD = try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)
        #expect(primaryMD.contains("identity \"Agency\""))
        let agencyMD = try String(contentsOf: CLIProfile(directory: agency.cliProfile(in: e.home.paths)).claudeMD, encoding: .utf8)
        #expect(agencyMD.contains("identity \"Ruben\""))
        let registry = try IdentityRegistry.load(e.brain.identitiesFile).identities
        #expect(registry["ruben"]?.name == "Agency" && registry["agency"]?.name == "Ruben")
    }

    @Test func swappingTheNamesOfTwoSecondariesKeepsEachAppOnItsOwnFolders() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let work = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try e.manager.swapNames("work", with: "client")
        #expect(try e.store.load().identity(slug: "work")?.name == "Client")
        #expect(try e.store.load().identity(slug: "client")?.name == "Work")
        #expect(appsInLaunchersDir(e) == ["Client.app", "Work.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Client")).dataDir == work.desktopData(in: e.home.paths).path)
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Work")).dataDir == client.desktopData(in: e.home.paths).path)
    }

    @Test func swappingNamesWithAnOpenSecondaryChangesNothing() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let agency = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        let exe = e.claude.executable.path, data = agency.desktopData(in: e.home.paths).path
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath, claudeAppURL: e.claude.url,
                                      registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        #expect(throws: BrainmergeError.identityRunning("agency")) { try manager.swapNames("ruben", with: "agency") }
        #expect(try e.store.load().identities.map(\.name) == ["Ruben", "Agency"])
        #expect(appsInLaunchersDir(e) == ["Agency.app"])
    }

    @Test func swappingNamesWithoutClaudeChangesNothing() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        try FileManager.default.removeItem(at: e.claude.url)
        #expect(throws: BrainmergeError.self) { try e.manager.swapNames("ruben", with: "agency") }
        #expect(try e.store.load().identities.map(\.name) == ["Ruben", "Agency"])
        #expect(appsInLaunchersDir(e) == ["Agency.app"])
    }

    /// Files the swap or a rename must not touch when it fails, with a date in the past: a write would change it.
    func pinDates(_ urls: [URL]) throws {
        for url in urls {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: url.path)
        }
    }

    func dates(_ urls: [URL]) throws -> [Date?] {
        try urls.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
    }

    /// The secondary's photo went missing, so its app cannot be built: the swap fails before anything is written.
    /// Both accounts keep their names everywhere (state, Claude's instructions, the memory's list), and the Dock app
    /// that was there still opens its account.
    @Test func aSwapThatCannotBuildAnAppLeavesBothAccountsAsTheyWere() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Agency")
        request.logo = try FakeIcon.orangePNG(in: e.home.url)
        let agency = try e.manager.add(request)
        try FileManager.default.removeItem(at: try #require(request.logo))
        let agencyMD = CLIProfile(directory: agency.cliProfile(in: e.home.paths)).claudeMD
        let untouched = [e.home.paths.stateFile, e.primaryProfile.claudeMD, agencyMD, e.brain.identitiesFile]
        try pinDates(untouched)

        #expect(throws: (any Error).self) { try e.manager.swapNames("ruben", with: "agency") }

        #expect(try e.store.load().identities.map(\.name) == ["Ruben", "Agency"])
        #expect(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8).contains("identity \"Ruben\""))
        #expect(try String(contentsOf: agencyMD, encoding: .utf8).contains("identity \"Agency\""))
        let registry = try IdentityRegistry.load(e.brain.identitiesFile).identities
        #expect(registry["ruben"]?.name == "Ruben" && registry["agency"]?.name == "Agency")
        // Nothing was written before the apps were ready: no temporary name ever reached a file.
        #expect(try dates(untouched) == Array(repeating: Date(timeIntervalSince1970: 1_700_000_000), count: untouched.count))
        #expect(appsInLaunchersDir(e) == ["Agency.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Agency")).dataDir == agency.desktopData(in: e.home.paths).path)
    }

    /// A rename whose new app cannot be built keeps the old name everywhere, and the old app in the Dock.
    @Test func aRenameThatCannotBuildItsAppChangesNothing() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Agency")
        request.logo = try FakeIcon.orangePNG(in: e.home.url)
        let agency = try e.manager.add(request)
        try FileManager.default.removeItem(at: try #require(request.logo))
        let agencyMD = CLIProfile(directory: agency.cliProfile(in: e.home.paths)).claudeMD

        #expect(throws: (any Error).self) { try e.manager.update(slug: "agency", name: "Agency", tint: nil, logo: nil) }

        #expect(try e.store.load().identity(slug: "agency")?.name == "Agency")
        #expect(try String(contentsOf: agencyMD, encoding: .utf8).contains("identity \"Agency\""))
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["agency"]?.name == "Agency")
        #expect(appsInLaunchersDir(e) == ["Agency.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Agency")).dataDir == agency.desktopData(in: e.home.paths).path)
    }

    /// Without Claude installed, a secondary's app cannot be rebuilt: the old one stays where it is.
    @Test func aRenameWithoutClaudeKeepsTheOldApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try FileManager.default.removeItem(at: e.claude.url)
        #expect(throws: (any Error).self) { try e.manager.update(slug: "client", name: "Studio", tint: nil, logo: nil) }
        #expect(try e.store.load().identity(slug: "client")?.name == "Client")
        #expect(appsInLaunchersDir(e) == ["Client.app"])
    }

    /// The primary's own app follows the same order: a rename that cannot build the new app keeps the old one.
    @Test func thePrimarysOwnAppSurvivesARenameThatCannotBuild() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let photo = try FakeIcon.orangePNG(in: e.home.url)
        _ = try e.manager.update(slug: "ruben", name: nil, tint: nil, logo: photo, ownApp: true)
        try FileManager.default.removeItem(at: photo)
        #expect(throws: (any Error).self) { try e.manager.update(slug: "ruben", name: "Ruben C", tint: nil, logo: nil) }
        #expect(try e.store.load().primary?.name == "Ruben")
        #expect(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8).contains("identity \"Ruben\""))
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Ruben")).openApp == e.claude.url.path)
    }

    /// Two tinted copies (or launchers) each take the other's name: no temporary app, no orphan copy.
    @Test func swappingLeavesNoTemporaryAppBehind() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        var work = IdentityManager.AddRequest(name: "Work"); work.iconMode = .tintedClone
        _ = try e.manager.add(work)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try e.manager.swapNames("work", with: "client")
        #expect(appsInLaunchersDir(e) == ["Client (Claude).app", "Work.app"])
        #expect(try e.store.load().identity(slug: "work")?.builtForClaudeVersion == e.claude.version)
    }

    // MARK: The primary: Claude itself

    /// A manager that sees the primary Claude running (the real Claude's command line: no --user-data-dir).
    func withClaudeOpen(_ e: ManagerEnv) -> IdentityManager {
        let exe = e.claude.executable.path
        return IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath, claudeAppURL: e.claude.url,
                               registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe)\n" }))
    }

    /// Every file of an app bundle, byte for byte.
    func files(of app: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let walk = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in walk where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[url.path] = try Data(contentsOf: url)
        }
        return files
    }

    @Test func editingThePrimaryWhileClaudeRunsSucceeds() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let manager = withClaudeOpen(e)
        #expect(try manager.isRunning(try #require(try e.store.load().primary)))
        let updated = try manager.update(slug: "ruben", name: "Ruben C", tint: .green, logo: nil, note: "Personal")
        #expect(updated.name == "Ruben C" && updated.tint == .green && updated.note == "Personal")
        #expect(try e.store.load().primary == updated)
        #expect(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8).contains("identity \"Ruben C\""))
        #expect(try IdentityRegistry.load(e.brain.identitiesFile).identities["ruben"] == IdentityRegistry.Entry(name: "Ruben C", tint: "green"))
        // Its memory still waits for Claude to quit: moving the memory links is not atomic.
        _ = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        #expect(throws: BrainmergeError.identityRunning("ruben")) { try manager.setBrain(of: "ruben", to: "work") }
        #expect(try e.store.load().primary?.brain == nil)
    }

    @Test func thePrimaryGetsAnOpenerAppAndClaudeIsUntouched() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let claudeBefore = try files(of: e.claude.url)
        let manager = withClaudeOpen(e)

        let on = try manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, ownApp: true)
        let app = e.home.paths.launcherApp(name: "Ruben")
        #expect(on.ownApp == true)
        #expect(try e.store.load().primary?.ownApp == true)
        #expect(on.appURL(in: e.home.paths) == app)
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
        #expect(try launcherConfig(app) == LauncherConfig(openApp: e.claude.url.path))
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/Resources/icon.icns").path))

        // It follows the name; switched off, it goes.
        _ = try manager.update(slug: "ruben", name: "Ruben C", tint: .green, logo: nil)
        #expect(appsInLaunchersDir(e) == ["Ruben C.app"])
        let off = try manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, ownApp: false)
        #expect(off.ownApp == false && off.appURL(in: e.home.paths) == nil)
        #expect(appsInLaunchersDir(e).isEmpty)

        // Claude itself: not a byte changed, and never a copy of it.
        #expect(try files(of: e.claude.url) == claudeBefore)
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.tintedClone(name: "Ruben").path))
    }

    @Test func thePrimaryNeverGetsATintedCopy() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let claudeBefore = try files(of: e.claude.url)
        #expect(throws: BrainmergeError.primaryIsClaude) { try e.manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, iconMode: .tintedClone) }
        #expect(try e.store.load().primary?.iconMode == .launcher)
        #expect(appsInLaunchersDir(e).isEmpty)
        // Even a state that asks for one (edited by hand) only ever gets the opener.
        var state = try e.store.load()
        state.identities[0].iconMode = .tintedClone
        state.identities[0].ownApp = true
        try e.store.save(state)
        try e.manager.rebuild(slug: "ruben")
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Ruben")).openApp == e.claude.url.path)
        #expect(try files(of: e.claude.url) == claudeBefore)
    }

    @Test func thePrimarysOwnAppIsRebuiltAndRemovedWhileClaudeRuns() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let manager = withClaudeOpen(e)
        try manager.rebuild(slug: "ruben")   // switched off: nothing to build
        #expect(appsInLaunchersDir(e).isEmpty)
        _ = try manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, ownApp: true)
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Ruben"))
        try manager.rebuild(slug: "ruben")
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
        try manager.remove(slug: "ruben", deleteData: false)
        #expect(appsInLaunchersDir(e).isEmpty)
        #expect(FileManager.default.fileExists(atPath: e.claude.url.path))
    }

    /// The opener is only rebuilt when what it shows changes: a note needs no Claude app.
    @Test func aNoteOnThePrimaryNeedsNoClaudeApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, ownApp: true)
        try FileManager.default.removeItem(at: e.claude.url)
        #expect(try e.manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, note: "Personal").note == "Personal")
        #expect(appsInLaunchersDir(e) == ["Ruben.app"])
    }

    @Test func swappingNamesWhileThePrimaryRunsRenamesBothApps() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let agency = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        let manager = withClaudeOpen(e)
        _ = try manager.update(slug: "ruben", name: nil, tint: nil, logo: nil, ownApp: true)
        try manager.swapNames("ruben", with: "agency")
        #expect(try e.store.load().identities.map(\.name) == ["Agency", "Ruben"])
        #expect(appsInLaunchersDir(e) == ["Agency.app", "Ruben.app"])
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Agency")).openApp == e.claude.url.path)
        #expect(try launcherConfig(e.home.paths.launcherApp(name: "Ruben")).dataDir == agency.desktopData(in: e.home.paths).path)
    }

    @Test func swappingNamesNeedsTwoKnownAccounts() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        #expect(throws: BrainmergeError.identityNotFound("nobody")) { try e.manager.swapNames("ruben", with: "nobody") }
        try e.manager.swapNames("ruben", with: "ruben")   // with itself: nothing to do
        #expect(try e.store.load().identities.map(\.name) == ["Ruben"])
    }
}
