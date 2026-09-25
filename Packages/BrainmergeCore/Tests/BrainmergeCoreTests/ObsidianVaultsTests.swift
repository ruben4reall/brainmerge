import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// The vaults offered to the graph come from Obsidian's own list, of which only the folders' paths are read.
@Suite struct ObsidianVaultsTests {
    func folder(_ url: URL, obsidian: Bool) throws {
        try FileManager.default.createDirectory(at: obsidian ? url.appending(path: ".obsidian") : url, withIntermediateDirectories: true)
    }

    @Test func vaultsAreReadFromObsidiansList() throws {
        let home = try TempHome(); defer { home.remove() }
        let notes = home.url.appending(path: "Documents/Notes Vault", directoryHint: .isDirectory)
        let work = home.url.appending(path: "Work", directoryHint: .isDirectory)
        try folder(notes, obsidian: true)
        try folder(work, obsidian: true)
        let list = home.paths.obsidianVaultList
        #expect(list.path.hasSuffix("Library/Application Support/obsidian/obsidian.json"))
        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"vaults": {
          "a1": {"path": "\(work.path)", "ts": 1727000000000, "open": true},
          "b2": {"path": "\(notes.path)", "ts": 1727000000001},
          "c3": {"path": "\(home.url.path)/Gone", "ts": 1},
          "d4": {"path": "\(work.path)/", "ts": 2},
          "e5": {"ts": 3}
        }, "frame": "hidden"}
        """
        try Data(json.utf8).write(to: list)
        // Folders that exist, once each, by name; a vault that was moved or deleted is not offered.
        #expect(ObsidianVaults.known(paths: home.paths).map(\.lastPathComponent) == ["Notes Vault", "Work"])
    }

    @Test func noListOrABrokenOneMeansNoVault() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(ObsidianVaults.known(paths: home.paths).isEmpty)
        let list = home.paths.obsidianVaultList
        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        for broken in ["", "{", #"{"vaults": 3}"#, #"{"vaults": {"a": {"path": 7}}}"#] {
            try Data(broken.utf8).write(to: list)
            #expect(ObsidianVaults.known(paths: home.paths).isEmpty)
        }
    }

    /// Documents, Desktop, Downloads, iCloud Drive, cloud storage and other disks are guarded by macOS with a consent
    /// prompt. Listing the vaults never looks into them, not even through a link: a vault there is offered as Obsidian
    /// lists it, and read only once picked. Elsewhere a vault whose folder is gone is still left out.
    @Test func guardedVaultsAreListedWithoutLookingAtThem() throws {
        let home = try TempHome(); defer { home.remove() }
        let h = home.url
        // None of these folders exist: a look at them would find nothing and leave them out.
        let link = h.appending(path: "Linked Vault")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: h.appending(path: "Documents/Real Vault"))
        let list = home.paths.obsidianVaultList
        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"vaults": {
          "a": {"path": "\(h.path)/Documents/Obsidian Vault"},
          "b": {"path": "\(h.path)/Library/Mobile Documents/iCloud~md~obsidian/Documents/Phone"},
          "c": {"path": "/Volumes/Travel Disk/Travel"},
          "d": {"path": "\(link.path)"},
          "e": {"path": "\(h.path)/Gone"}
        }}
        """
        try Data(json.utf8).write(to: list)
        #expect(ObsidianVaults.known(paths: home.paths).map(\.lastPathComponent) == ["Linked Vault", "Obsidian Vault", "Phone", "Travel"])
    }

    /// A chosen vault is let go only when its folder is really gone: one macOS or its permissions refuse to show is
    /// still there, and the graph then says it may not read it.
    @Test func aVaultIsGoneOnlyWhenItsFolderIs() throws {
        let home = try TempHome(); defer { home.remove() }
        let vault = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try folder(vault, obsidian: true)
        #expect(!ObsidianVaults.isGone(vault))
        #expect(ObsidianVaults.isGone(home.url.appending(path: "Nowhere")))
        let file = home.url.appending(path: "file.md")
        try Data("x".utf8).write(to: file)
        #expect(ObsidianVaults.isGone(file))
        let locked = home.url.appending(path: "Locked", directoryHint: .isDirectory)
        try folder(locked.appending(path: "Vault"), obsidian: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(!ObsidianVaults.isGone(locked.appending(path: "Vault")))
    }

    /// A folder picked by hand is a vault when Obsidian keeps its settings in it.
    @Test func aVaultHasItsObsidianFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        let vault = home.url.appending(path: "Vault", directoryHint: .isDirectory)
        let plain = home.url.appending(path: "Plain", directoryHint: .isDirectory)
        try folder(vault, obsidian: true)
        try folder(plain, obsidian: false)
        try Data("x".utf8).write(to: plain.appending(path: ".obsidian"))
        #expect(ObsidianVaults.isVault(vault))
        #expect(!ObsidianVaults.isVault(plain))
        #expect(!ObsidianVaults.isVault(home.url.appending(path: "Nowhere")))
    }
}
