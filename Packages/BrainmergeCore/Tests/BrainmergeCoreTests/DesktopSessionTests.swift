import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// A Claude data folder that logged in holds the app's own storage; one that only opened does not.
/// Only names are looked at, never a byte of their contents.
@Suite struct DesktopSessionTests {
    func dataDir(_ home: TempHome, _ entries: [String]) throws -> URL {
        let dir = home.url.appending(path: "Library/Application Support/Claude-work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for entry in entries {
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dir.appending(path: entry), withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: dir.appending(path: entry).deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("x".utf8).write(to: dir.appending(path: entry))
            }
        }
        return dir
    }

    @Test func aProfileThatNeverLoggedInHasNoSession() throws {
        let home = try TempHome(); defer { home.remove() }
        let dir = try dataDir(home, ["Session Storage/000001.log", "Preferences", "config.json"])
        #expect(!DesktopSession.hasSession(dataDir: dir))
        #expect(!DesktopSession.hasSession(dataDir: home.url.appending(path: "missing")))
    }

    @Test func aLoggedInProfileHasASession() throws {
        let home = try TempHome(); defer { home.remove() }
        let dir = try dataDir(home, ["Cookies", "Local Storage/leveldb/000003.log", "IndexedDB/https_claude.ai_0.indexeddb.leveldb/000003.log", "Session Storage/000001.log"])
        #expect(DesktopSession.hasSession(dataDir: dir))
    }

    @Test func cookiesAloneAreNotEnough() throws {
        let home = try TempHome(); defer { home.remove() }
        let dir = try dataDir(home, ["Cookies", "IndexedDB/"])
        #expect(!DesktopSession.hasSession(dataDir: dir))
    }
}
