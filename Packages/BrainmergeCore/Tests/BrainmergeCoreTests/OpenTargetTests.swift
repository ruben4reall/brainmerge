import Foundation
import Testing
import BrainmergeTestSupport
import LauncherGuard
@testable import BrainmergeCore

/// The primary's own app opens one thing only: Anthropic's Claude, at the path its builder pinned.
/// Everything here is checked without ever opening an app.
@Suite struct OpenTargetTests {
    static let installedClaude = "/Applications/Claude.app"

    func fakeClaude(in home: TempHome, folder: String = "") throws -> ClaudeApp {
        let dir = home.url.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try FakeClaudeApp.make(in: dir)
    }

    @Test func refusesAnythingButAnAbsolutePathToAnApp() {
        for path in ["", "Claude.app", "Applications/Claude.app", "/Applications/../Applications/Claude.app",
                     "/Applications/Claude.app/..", "/Applications/Claude", "/bin/echo"] {
            #expect(OpenTarget.refusal(openApp: path, pinned: path) == .notAnApp, "\(path)")
        }
    }

    @Test func refusesAPathOtherThanThePinnedOne() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try fakeClaude(in: home)
        let other = try fakeClaude(in: home, folder: "other")
        #expect(OpenTarget.refusal(openApp: other.url.path, pinned: claude.url.path) == .notPinned)
        #expect(OpenTarget.refusal(openApp: claude.url.path, pinned: nil) == .notPinned)
        #expect(OpenTarget.refusal(openApp: claude.url.path, pinned: claude.url.path + "/") == .notPinned)
    }

    @Test func refusesAnAppThatIsNotClaude() throws {
        let home = try TempHome(); defer { home.remove() }
        let claude = try fakeClaude(in: home)
        var plist = try Plist.read(claude.infoPlist)
        plist["CFBundleIdentifier"] = "com.example.notclaude"
        try Plist.write(plist, to: claude.infoPlist)
        #expect(OpenTarget.refusal(openApp: claude.url.path, pinned: claude.url.path) == .notClaude)
        // A bundle without an Info.plist is not Claude either.
        try FileManager.default.removeItem(at: claude.infoPlist)
        #expect(OpenTarget.refusal(openApp: claude.url.path, pinned: claude.url.path) == .notClaude)
    }

    /// Hand-made copies of Claude and Brainmerge's tinted copies carry Claude's bundle id: only Anthropic's signature tells them apart.
    @Test func refusesAClaudeNotSignedByAnthropic() throws {
        let home = try TempHome(); defer { home.remove() }
        let unsigned = try fakeClaude(in: home)
        #expect(!OpenTarget.isSignedByAnthropic(unsigned.url.path))
        #expect(OpenTarget.refusal(openApp: unsigned.url.path, pinned: unsigned.url.path) == .notSignedByAnthropic)
        let adHoc = try fakeClaude(in: home, folder: "adhoc")
        try Shell().check("/usr/bin/codesign", ["--force", "--sign", "-", adHoc.url.path])
        #expect(!OpenTarget.isSignedByAnthropic(adHoc.url.path))
        #expect(OpenTarget.refusal(openApp: adHoc.url.path, pinned: adHoc.url.path) == .notSignedByAnthropic)
    }

    /// The requirement matches the real Claude (read only, nothing is opened), so the opener does not refuse the one app it is for.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: OpenTargetTests.installedClaude)))
    func acceptsTheInstalledClaude() {
        #expect(OpenTarget.isSignedByAnthropic(Self.installedClaude))
        #expect(OpenTarget.refusal(openApp: Self.installedClaude, pinned: Self.installedClaude) == nil)
    }
}
