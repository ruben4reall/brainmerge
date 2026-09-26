import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ClaudeLocatorTests {
    /// A home with its own ~/Applications and a stand-in for /Applications, both temporary.
    struct Mac {
        let home: TempHome
        var own: URL { home.url.appending(path: "Applications", directoryHint: .isDirectory) }
        var system: URL { home.url.appending(path: "System Applications", directoryHint: .isDirectory) }
        init() throws {
            home = try TempHome()
            try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        }
        func locator(signed: @escaping @Sendable (String) -> Bool = { _ in true }, launchServices: [URL] = []) -> ClaudeLocator {
            ClaudeLocator(paths: home.paths, folders: [system, own], launchServices: { launchServices }, isSigned: signed)
        }
    }

    @Test func foundInTheHomeApplicationsWhenTheSystemFolderIsEmpty() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        let claude = try FakeClaudeApp.make(in: mac.own)
        #expect(mac.locator().locate(choice: nil) == claude.url)
    }

    @Test func theSystemFolderComesFirst() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        try FakeClaudeApp.make(in: mac.own)
        let system = try FakeClaudeApp.make(in: mac.system)
        #expect(mac.locator().locate(choice: nil) == system.url)
    }

    /// Claude.app at its usual place comes before any copy under another name, even one that sorts first ("Claude
    /// copy.app", a Finder duplicate) or sits in /Applications while Claude is in ~/Applications. Copies come after,
    /// newest first.
    @Test func claudeAtItsUsualPlaceComesBeforeCopies() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        func copy(_ name: String, in folder: URL, version: String) throws -> URL {
            let scratch = mac.home.url.appending(path: "scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let made = try FakeClaudeApp.make(in: scratch, version: version)
            let url = folder.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: made.url, to: url)
            return url
        }
        let old = try copy("Claude copy.app", in: mac.system, version: "2.1.0")
        let newer = try copy("Claude 2.app", in: mac.system, version: "2.9.0")
        let claude = try FakeClaudeApp.make(in: mac.own, version: "2.8.0")
        #expect(mac.locator().locate(choice: nil) == claude.url)
        #expect(mac.locator().candidates().map(\.url.lastPathComponent) == ["Claude.app", "Claude 2.app", "Claude copy.app"])
        try FileManager.default.removeItem(at: claude.url)
        #expect(mac.locator().locate(choice: nil) == newer)
        #expect(old.lastPathComponent == "Claude copy.app")
    }

    @Test func anUnsignedCopyIsRefused() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        let claude = try FakeClaudeApp.make(in: mac.own)
        let locator = mac.locator(signed: { _ in false })
        #expect(locator.locate(choice: nil) == nil)
        #expect(throws: BrainmergeError.claudeNotSigned(claude.url.path)) { try locator.validate(choice: claude.url) }
        #expect(BrainmergeError.claudeNotSigned("x").description
                == "This copy of Claude is not signed by Anthropic. Brainmerge only opens the official app.")
    }

    @Test func brainmergesOwnAppsAndHandMadeCopiesAreLeftOut() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        try FileManager.default.createDirectory(at: mac.home.paths.launchersDir, withIntermediateDirectories: true)
        let tinted = try FakeClaudeApp.make(in: mac.home.paths.launchersDir)
        let handMade = try HandMadeApp.make("Claude Second", in: mac.own, script: HandMadeApp.ownersScript)
        let locator = mac.locator(launchServices: [tinted.url, handMade])
        #expect(locator.candidates().isEmpty)
        #expect(throws: (any Error).self) { try locator.validate(choice: handMade) }
    }

    @Test func thePersonsChoiceWins() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        try FakeClaudeApp.make(in: mac.system)
        let elsewhere = mac.home.url.appending(path: "Tools", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let chosen = try FakeClaudeApp.make(in: elsewhere)
        #expect(mac.locator().locate(choice: chosen.url.path) == chosen.url)
        // A choice that is gone falls back to the usual order.
        try FileManager.default.removeItem(at: chosen.url)
        #expect(mac.locator().locate(choice: chosen.url.path)?.deletingLastPathComponent().lastPathComponent == "System Applications")
    }

    @Test func launchServicesFindsTheRestNewestFirst() throws {
        let mac = try Mac(); defer { mac.home.remove() }
        let a = mac.home.url.appending(path: "A", directoryHint: .isDirectory), b = mac.home.url.appending(path: "B", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let old = try FakeClaudeApp.make(in: a, version: "2.9.0"), new = try FakeClaudeApp.make(in: b, version: "2.10.0")
        #expect(mac.locator(launchServices: [old.url, new.url]).locate(choice: nil) == new.url)
    }

    @Test func theChoiceIsSavedInTheState() throws {
        let home = try TempHome(); defer { home.remove() }
        var state = AppState()
        state.claudeAppPath = "/Somewhere/Claude.app"
        try StateStore(paths: home.paths).save(state)
        #expect(try StateStore(paths: home.paths).load().claudeAppPath == "/Somewhere/Claude.app")
    }
}
