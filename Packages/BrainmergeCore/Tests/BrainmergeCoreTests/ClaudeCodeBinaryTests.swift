import Foundation
import Testing
import BrainmergeTestSupport
import LauncherGuard
@testable import BrainmergeCore

/// Which Claude Code "Check limits" may run: found at an absolute path, never through PATH, and signed by Anthropic.
/// Files here are fakes in a temporary folder; the real Claude Code is never run, nor its signature read.
@Suite struct ClaudeCodeBinaryTests {
    /// A file standing for a Claude Code binary, at `path` under the temporary folder.
    @discardableResult
    func file(_ path: String, in home: TempHome) throws -> URL {
        let url = home.url.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func link(_ path: String, to destination: String, in home: TempHome) throws {
        let url = home.url.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    /// Records which paths were checked, and says yes only for `signed`.
    final class Verifier: @unchecked Sendable {
        let signed: Set<String>
        private(set) var asked: [String] = []
        init(signed: Set<String>) { self.signed = signed }
        func check(_ path: String) -> Bool { asked.append(path); return signed.contains(path) }
    }

    @Test func looksInTheInstallersFoldersInOrder() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(ClaudeCodeBinary.candidates(home: home) == ["/Users/someone/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
    }

    /// The native installer's link points into a folder of versions: the version it points to is checked and run,
    /// so the link cannot be swapped between the check and the run.
    @Test func followsTheLinkAndRunsWhatItPointsTo() throws {
        let home = try TempHome(); defer { home.remove() }
        let version = try file(".local/share/claude/versions/2.1.280", in: home)
        try link(".local/bin/claude", to: version.path, in: home)
        let real = version.resolvingSymlinksInPath().path
        let verifier = Verifier(signed: [real])
        let found = ClaudeCodeBinary.resolve(candidates: [home.url.appending(path: ".local/bin/claude").path], isSigned: verifier.check)
        #expect(found == .found(real))
        #expect(verifier.asked == [real])
    }

    @Test func followsARelativeLink() throws {
        let home = try TempHome(); defer { home.remove() }
        let version = try file(".local/share/claude/versions/2.1.281", in: home)
        try link(".local/bin/claude", to: "../share/claude/versions/2.1.281", in: home)
        let real = version.resolvingSymlinksInPath().path
        let found = ClaudeCodeBinary.resolve(candidates: [home.url.appending(path: ".local/bin/claude").path], isSigned: { $0 == real })
        #expect(found == .found(real))
    }

    @Test func takesTheFirstPlaceThatHasOne() throws {
        let home = try TempHome(); defer { home.remove() }
        let second = try file("homebrew/claude", in: home).resolvingSymlinksInPath().path
        let third = try file("local/claude", in: home).resolvingSymlinksInPath().path
        let candidates = [home.url.appending(path: "missing/claude").path, home.url.appending(path: "homebrew/claude").path,
                          home.url.appending(path: "local/claude").path]
        let verifier = Verifier(signed: [second, third])
        #expect(ClaudeCodeBinary.resolve(candidates: candidates, isSigned: verifier.check) == .found(second))
        #expect(verifier.asked == [second])
    }

    /// The first Claude Code found is the one the person uses: when Anthropic did not sign it, nothing else is tried.
    @Test func refusesTheFirstOneFoundWhenAnthropicDidNotSignIt() throws {
        let home = try TempHome(); defer { home.remove() }
        let first = try file("first/claude", in: home)
        let second = try file("second/claude", in: home).resolvingSymlinksInPath().path
        let verifier = Verifier(signed: [second])
        let found = ClaudeCodeBinary.resolve(candidates: [first.path, home.url.appending(path: "second/claude").path], isSigned: verifier.check)
        #expect(found == .notSigned(first.path))
        #expect(verifier.asked == [first.resolvingSymlinksInPath().path])
    }

    @Test func skipsABrokenLinkAndAFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        try link("broken/claude", to: "/nonexistent/claude-version", in: home)
        try FileManager.default.createDirectory(at: home.url.appending(path: "folder/claude"), withIntermediateDirectories: true)
        let last = try file("last/claude", in: home).resolvingSymlinksInPath().path
        let candidates = ["broken/claude", "folder/claude", "last/claude"].map { home.url.appending(path: $0).path }
        #expect(ClaudeCodeBinary.resolve(candidates: candidates, isSigned: { _ in true }) == .found(last))
    }

    @Test func saysWhenThereIsNone() throws {
        let home = try TempHome(); defer { home.remove() }
        let verifier = Verifier(signed: [])
        #expect(ClaudeCodeBinary.resolve(candidates: [home.url.appending(path: "none/claude").path], isSigned: verifier.check) == .notFound)
        #expect(verifier.asked.isEmpty)
    }

    // The real check, through the Security framework, on files that are not Claude Code.

    @Test func aScriptIsNotSignedByAnthropic() throws {
        let home = try TempHome(); defer { home.remove() }
        let script = try file("claude", in: home)
        #expect(!ClaudeCodeBinary.isSignedByAnthropic(script.path))
    }

    @Test func aProgramSignedBySomeoneElseIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        let copy = home.url.appending(path: "claude")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: copy)
        #expect(!ClaudeCodeBinary.isSignedByAnthropic(copy.path))
        try Shell().check("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", ClaudeCodeBinary.identifier, copy.path])
        #expect(!ClaudeCodeBinary.isSignedByAnthropic(copy.path), "an ad hoc signature with Claude Code's identifier is not Anthropic's")
    }

    /// The requirement works on a bare program signed by Anthropic (a helper inside the installed Claude, read only,
    /// never run), and pins the identifier: that helper is not Claude Code.
    static let anthropicHelper = "/Applications/Claude.app/Contents/Helpers/chrome-native-host"
    @Test(.enabled(if: FileManager.default.fileExists(atPath: ClaudeCodeBinaryTests.anthropicHelper)))
    func theRequirementReadsAnthropicsSignatureOnAProgram() {
        #expect(OpenTarget.isSignedByAnthropic(Self.anthropicHelper, identifier: "chrome-native-host"))
        #expect(!ClaudeCodeBinary.isSignedByAnthropic(Self.anthropicHelper))
    }
}
