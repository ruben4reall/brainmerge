import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct CLIProfileTests {
    func settings(_ profile: CLIProfile) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: profile.settingsFile)) as! [String: Any]
    }

    @Test func createsMinimalProfileInheritingBasicsOnly() throws {
        let home = try TempHome(); defer { home.remove() }
        let primary = CLIProfile(directory: home.paths.primaryCLIProfile)
        try FileManager.default.createDirectory(at: primary.skillsDir, withIntermediateDirectories: true)
        let primarySettings = """
        {"model":"opus[1m]","language":"french","hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]},"permissions":{"defaultMode":"bypassPermissions"}}
        """
        try Data(primarySettings.utf8).write(to: primary.settingsFile)

        let profile = try CLIProfile.create(at: home.paths.cliProfile(slug: "client", isPrimary: false), inheritingFrom: primary)
        let s = try settings(profile)
        #expect(s["model"] as? String == "opus[1m]")
        #expect(s["language"] as? String == "french")
        #expect(s["hooks"] == nil)
        #expect(s["permissions"] == nil)
        #expect(FileManager.default.fileExists(atPath: profile.projectsDir.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: profile.skillsDir.path) == primary.skillsDir.path)
        #expect(profile.exists)
    }

    @Test func existingProfileIsLeftAlone() throws {
        let home = try TempHome(); defer { home.remove() }
        let dir = home.url.appending(path: ".claude-existing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model":"sonnet"}"#.utf8).write(to: dir.appending(path: "settings.json"))
        let profile = try CLIProfile.create(at: dir, inheritingFrom: nil)
        #expect(try settings(profile)["model"] as? String == "sonnet")
    }

    @Test func projectPathsComeFromClaudeJSON() throws {
        let home = try TempHome(); defer { home.remove() }
        let profile = try CLIProfile.create(at: home.paths.primaryCLIProfile, inheritingFrom: nil)
        #expect(try profile.projectPaths() == [])
        try Data(#"{"projects":{"/Users/r/atelier":{"allowedTools":[]},"/Users/r":{}},"other":1}"#.utf8)
            .write(to: profile.claudeJSON)
        #expect(try profile.projectPaths() == ["/Users/r", "/Users/r/atelier"])
    }

    @Test func projectPathsAreOnlyTheKeysWhateverTheValues() throws {
        let home = try TempHome(); defer { home.remove() }
        let profile = try CLIProfile.create(at: home.paths.cliProfile(slug: "client", isPrimary: false), inheritingFrom: nil)
        // Project settings can hold MCP servers with secrets: only the paths come out, whatever the values look like.
        try Data(#"{"projects":{"/x/a":{"mcpServers":{"db":{"env":{"DB_TOKEN":"secret"}}}},"/x/b":1,"/x/c":null,"/x/d":[]},"oauthAccount":{}}"#.utf8)
            .write(to: profile.claudeJSON)
        #expect(try profile.projectPaths() == ["/x/a", "/x/b", "/x/c", "/x/d"])
        try Data(#"{"projects":[]}"#.utf8).write(to: profile.claudeJSON)
        #expect(try profile.projectPaths() == [])
        try Data(#"{"other":{"projects":{"/x/z":{}}}}"#.utf8).write(to: profile.claudeJSON)
        #expect(try profile.projectPaths() == [])
        try Data(#"["not an object"]"#.utf8).write(to: profile.claudeJSON)
        #expect(throws: BrainmergeError.self) { try profile.projectPaths() }
        try Data(#"{"projects":{"/x/a""#.utf8).write(to: profile.claudeJSON)
        #expect(throws: BrainmergeError.self) { try profile.projectPaths() }
    }

    @Test func primaryProfileReadsClaudeJSONBesideItsFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        let profile = try CLIProfile.create(at: home.paths.primaryCLIProfile, inheritingFrom: nil)
        try Data(#"{"installMethod":"native"}"#.utf8).write(to: profile.directory.appending(path: ".claude.json"))
        try Data(#"{"projects":{"/Users/r/atelier":{}}}"#.utf8).write(to: home.url.appending(path: ".claude.json"))
        #expect(profile.claudeJSON.path == home.url.appending(path: ".claude.json").path)
        #expect(try profile.projectPaths() == ["/Users/r/atelier"])
    }

    @Test func projectsUnionSessionFoldersAndKnownPaths() throws {
        let home = try TempHome(); defer { home.remove() }
        let profile = try CLIProfile.create(at: home.paths.cliProfile(slug: "client", isPrimary: false), inheritingFrom: nil)
        try Data(#"{"projects":{"/x/a":{},"/x/c":{}}}"#.utf8).write(to: profile.claudeJSON)
        try FileManager.default.createDirectory(at: profile.projectsDir.appending(path: "-x-a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile.projectsDir.appending(path: "-x-b"), withIntermediateDirectories: true)
        #expect(try profile.projects() == [ProjectRef(slug: "-x-a", path: "/x/a"), ProjectRef(slug: "-x-b", path: nil), ProjectRef(slug: "-x-c", path: "/x/c")])
    }
}
