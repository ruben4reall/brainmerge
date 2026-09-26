import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// What attaching, adding and removing an account must never do to the person's files and notes.
@Suite struct IdentityWiringSafetyTests {
    let fm = FileManager.default

    func atelierLink(_ e: ManagerEnv, in profile: CLIProfile) -> URL {
        profile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier), directoryHint: .isDirectory).appending(path: "memory")
    }

    @Test func aCLAUDEFileThatIsNotUTF8IsNeverReplaced() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        // "# Règles\n" as saved by an editor set to Western (Latin-1).
        let latin1 = Data([0x23, 0x20, 0x52, 0xE8, 0x67, 0x6C, 0x65, 0x73, 0x0A])
        try latin1.write(to: e.primaryProfile.claudeMD)
        let error = #expect(throws: BrainmergeError.self) { try e.manager.adoptPrimary(name: "Perso") }
        if case .unreadableText = error {} else { Issue.record("unexpected \(String(describing: error))") }
        #expect(try Data(contentsOf: e.primaryProfile.claudeMD) == latin1)
        #expect(try !HookInstaller.isInstalled(settingsFile: e.primaryProfile.settingsFile))
        #expect(try e.store.load().primary == nil)
    }

    @Test func theFirstAccountsNameFollowsTheNameRules() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        #expect(throws: BrainmergeError.nameInvalid) { try e.manager.adoptPrimary(name: " \n ") }
        let primary = try e.manager.adoptPrimary(name: "Me\n@/etc/hosts")
        #expect(primary.name == "Me @/etc/hosts")
        #expect(!(try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)).contains("\n@/etc/hosts"))
        // Adopted again after it was removed, it cannot take a name another account has.
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try e.manager.remove(slug: primary.slug, deleteData: false)
        #expect(throws: BrainmergeError.identityNameTaken("work")) { try e.manager.adoptPrimary(name: "work") }
    }

    @Test func sharedHistoryNeedsTheFirstAccountsMemory() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let link = atelierLink(e, in: e.primaryProfile)
        var own = IdentityManager.AddRequest(name: "Client")
        own.sharedHistory = true; own.ownBrain = true
        #expect(throws: BrainmergeError.sharedHistoryNeedsSameMemory) { try e.manager.add(own) }
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "atelier").path)
        #expect(try e.store.load().identities.count == 1 && e.store.load().brains.count == 1)

        var shared = IdentityManager.AddRequest(name: "Client"); shared.sharedHistory = true
        _ = try e.manager.add(shared)
        let other = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        #expect(throws: BrainmergeError.sharedHistoryNeedsSameMemory) { try e.manager.setBrain(of: "client", to: other.id) }
        #expect(throws: BrainmergeError.sharedHistoryNeedsSameMemory) { try e.manager.setBrain(of: "perso", to: other.id) }
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "atelier").path)
    }

    @Test func aFailedAddLeavesNoWiringBehind() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let identitiesBefore = try Data(contentsOf: e.brain.identitiesFile)
        let cli = e.home.url.appending(path: ".claude-second", directoryHint: .isDirectory)
        try fm.createDirectory(at: cli, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cli.appending(path: "settings.json"))
        try Data("# Mine\n".utf8).write(to: cli.appending(path: "CLAUDE.md"))
        try JSONSerialization.data(withJSONObject: ["projects": [e.atelier: [:]]]).write(to: cli.appending(path: ".claude.json"))
        let real = atelierLink(e, in: CLIProfile(directory: cli))
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("mine\n".utf8).write(to: real.appending(path: "note.md"))
        let notAnImage = e.home.url.appending(path: "photo.png")
        try Data("not an image".utf8).write(to: notAnImage)

        var request = IdentityManager.AddRequest(name: "Work")
        request.adoptCLIProfile = cli; request.logo = notAnImage
        #expect(throws: (any Error).self) { try e.manager.add(request) }

        let claudeMD = try String(contentsOf: cli.appending(path: "CLAUDE.md"), encoding: .utf8)
        #expect(claudeMD.hasPrefix("# Mine") && !ManagedBlock.contains(claudeMD))
        #expect(try !HookInstaller.isInstalled(settingsFile: cli.appending(path: "settings.json")))
        let ledger = TouchedLedger(brain: e.brain, slug: "work")
        #expect(!fm.fileExists(atPath: ledger.file.path) && !fm.fileExists(atPath: ledger.sending.path))
        #expect(try Data(contentsOf: e.brain.identitiesFile) == identitiesBefore)
        #expect(!fm.fileExists(atPath: e.home.paths.desktopData(slug: "work", isPrimary: false).path))
        #expect(try e.store.load().identity(slug: "work") == nil)
        // The note is never lost: it is in the memory.
        #expect(try String(contentsOf: e.brain.memoryDir(forProject: "atelier").appending(path: "note.md"), encoding: .utf8) == "mine\n")
    }

    @Test func aNewAccountNeverTakesFoldersItDidNotCreate() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        // Left by a removed account: still signed in, never handed to a new one.
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try e.manager.remove(slug: "work", deleteData: false)
        #expect(try e.manager.add(IdentityManager.AddRequest(name: "Work")).slug == "work-2")
        // Made by hand before Brainmerge, with any letter case: never taken, never deleted.
        let handMade = e.home.url.appending(path: ".claude-client", directoryHint: .isDirectory)
        try fm.createDirectory(at: handMade, withIntermediateDirectories: true)
        let handMadeData = e.home.url.appending(path: "Library/Application Support/Claude-Studio", directoryHint: .isDirectory)
        try fm.createDirectory(at: handMadeData, withIntermediateDirectories: true)
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        #expect(client.slug == "client-2")
        #expect(try e.manager.add(IdentityManager.AddRequest(name: "Studio")).slug == "studio-2")
        try e.manager.remove(slug: client.slug, deleteData: true)
        #expect(fm.fileExists(atPath: handMade.path) && fm.fileExists(atPath: handMadeData.path))
        #expect(!fm.fileExists(atPath: client.cliProfile(in: e.home.paths).path))
    }

    @Test func aMissingPhotoNeverBlocksAChange() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let photo = try FakeIcon.orangePNG(in: e.home.url)
        var request = IdentityManager.AddRequest(name: "Client"); request.logo = photo
        _ = try e.manager.add(request)
        try fm.removeItem(at: photo)
        let updated = try e.manager.update(slug: "client", name: "Clients", tint: nil, logo: nil, note: "Day job")
        #expect(updated.name == "Clients" && updated.note == "Day job")
        #expect(fm.fileExists(atPath: e.home.paths.launcherApp(name: "Clients").appending(path: "Contents/Resources/icon.icns").path))
    }
}
