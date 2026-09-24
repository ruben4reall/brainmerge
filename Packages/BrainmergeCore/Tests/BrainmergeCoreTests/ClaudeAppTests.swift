import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ClaudeAppTests {
    @Test func detectsVersionAndPaths() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeClaudeApp.make(in: home.url, version: "2.7032.0")
        #expect(app.version == "2.7032.0")
        #expect(app.bundleIdentifier == "com.anthropic.claudefordesktop")
        #expect(app.executable.path.hasSuffix("Claude.app/Contents/MacOS/Claude"))
        #expect(app.icon.lastPathComponent == "electron.icns")
    }
    @Test func missingAppThrows() throws {
        let home = try TempHome(); defer { home.remove() }
        let url = home.url.appending(path: "Nope.app", directoryHint: .isDirectory)
        #expect(throws: BrainmergeError.claudeAppNotFound(url.path)) { try ClaudeApp.detect(at: url) }
    }
    @Test func environmentOverride() {
        #expect(ClaudeApp.defaultURL(environment: ["BRAINMERGE_CLAUDE_APP": "/tmp/X.app"]).path == "/tmp/X.app")
        #expect(ClaudeApp.defaultURL(environment: [:]).path == "/Applications/Claude.app")
    }
}
