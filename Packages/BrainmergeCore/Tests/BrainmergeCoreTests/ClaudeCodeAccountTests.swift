import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// The account Claude Code records for display in `.claude.json`: three fields, nothing else, never from the wrong file.
@Suite struct ClaudeCodeAccountTests {
    /// A real-looking `.claude.json`: the display fields sit next to identifiers, plan and limits, and the file also
    /// holds an API key, a token cache and an MCP server's secrets. Only the three display fields may come out.
    static let full = """
    {
      "primaryApiKey": "sk-SENTINEL-API-KEY",
      "customApiKeyResponses": {"approved": ["SENTINEL-APPROVED"]},
      "oauth:tokenCache": "SENTINEL-TOKEN-CACHE",
      "cachedUsageUtilization": {"five_hour": 0.42, "note": "SENTINEL-USAGE"},
      "userID": "SENTINEL-USER-ID",
      "projects": {"/Users/alex/site": {"mcpServers": {"db": {"env": {"DB_TOKEN": "SENTINEL-MCP-TOKEN"}}}}},
      "oauthAccount": {
        "accountUuid": "SENTINEL-ACCOUNT-UUID",
        "organizationUuid": "SENTINEL-ORG-UUID",
        "billingType": "SENTINEL-BILLING",
        "userRateLimitTier": "SENTINEL-RATE-TIER",
        "organizationRateLimitTier": "SENTINEL-ORG-TIER",
        "seatTier": "SENTINEL-SEAT",
        "fullName": "SENTINEL-FULL-NAME",
        "emailAddress": "alex@example.com",
        "displayName": "Alex",
        "organizationName": "Acme Studio"
      }
    }
    """

    func profile(_ home: TempHome, _ name: String) throws -> CLIProfile {
        let dir = home.url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return CLIProfile(directory: dir)
    }

    func write(_ json: String, to url: URL) throws { try Data(json.utf8).write(to: url) }

    @Test func readsOnlyTheThreeDisplayFields() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        try write(Self.full, to: work.directory.appending(path: ".claude.json"))
        let account = try #require(ClaudeCodeAccount.read(profile: work))
        #expect(account == ClaudeCodeAccount(email: "alex@example.com", displayName: "Alex", organization: "Acme Studio"))
        // Nothing else of the file lives in the value: not an identifier, not the plan, not a key or a token.
        let everything = String(reflecting: account) + String(describing: account)
        #expect(!everything.contains("SENTINEL"), "\(everything)")
    }

    @Test func aLoggedOutProfileShowsNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        let file = work.directory.appending(path: ".claude.json")
        // Never logged in, or logged out: Claude Code removes the entry.
        try write(#"{"projects":{},"userID":"u"}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        try write(#"{"oauthAccount":null}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        // An entry without an email names nobody.
        try write(#"{"oauthAccount":{"displayName":"Alex"}}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        try write(#"{"oauthAccount":{"emailAddress":"  "}}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
    }

    @Test func aMissingOrBrokenFileShowsNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        try write(#"{"oauthAccount":{"emailAddress":"alex@exa"#, to: work.directory.appending(path: ".claude.json"))
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        try write("", to: work.directory.appending(path: ".claude.json"))
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
        try write(#"["not", "an", "object"]"#, to: work.directory.appending(path: ".claude.json"))
        #expect(ClaudeCodeAccount.read(profile: work) == nil)
    }

    @Test func anEntryFilledFromTheAppWithOnlyAnEmailStillShows() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        // Other fields of an unexpected type do not hide the email either.
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com","displayName":42}}"#, to: work.directory.appending(path: ".claude.json"))
        #expect(ClaudeCodeAccount.read(profile: work) == ClaudeCodeAccount(email: "alex@example.com", displayName: nil, organization: nil))
    }

    @Test func thePersonalOrganizationIsNotAnOrganization() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        let file = work.directory.appending(path: ".claude.json")
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com","displayName":"Alex","organizationName":"alex@example.com's Organization"}}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work)?.organization == nil)
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com","displayName":"","organizationName":"Acme"}}"#, to: file)
        #expect(ClaudeCodeAccount.read(profile: work) == ClaudeCodeAccount(email: "alex@example.com", displayName: nil, organization: "Acme"))
    }

    @Test func thePrimaryReadsTheFileBesideItsFolderEvenWithTheStubInside() throws {
        let home = try TempHome(); defer { home.remove() }
        let primary = CLIProfile(directory: home.paths.primaryCLIProfile)
        try FileManager.default.createDirectory(at: primary.directory, withIntermediateDirectories: true)
        // ~/.claude/.claude.json is a stub, even one that once recorded another account; ~/.claude.json is Claude Code's file.
        try write(#"{"machineID":"m","oauthAccount":{"emailAddress":"stub@example.com"}}"#, to: primary.directory.appending(path: ".claude.json"))
        try write(#"{"projects":{},"oauthAccount":{"emailAddress":"ruben@example.com","displayName":"Ruben"}}"#, to: home.url.appending(path: ".claude.json"))
        #expect(primary.accountFile.path == home.url.appending(path: ".claude.json").path)
        #expect(ClaudeCodeAccount.read(profile: primary)?.email == "ruben@example.com")
    }

    @Test func aConfigDirProfileReadsTheFileInsideIt() throws {
        let home = try TempHome(); defer { home.remove() }
        let secondary = try profile(home, ".claude-second")
        try write(#"{"oauthAccount":{"emailAddress":"agency@example.com"}}"#, to: secondary.directory.appending(path: ".claude.json"))
        // A ~/.claude.json of the primary next door never leaks into another profile.
        try write(#"{"oauthAccount":{"emailAddress":"ruben@example.com"}}"#, to: home.url.appending(path: ".claude.json"))
        #expect(secondary.accountFile.path == secondary.directory.appending(path: ".claude.json").path)
        #expect(ClaudeCodeAccount.read(profile: secondary)?.email == "agency@example.com")
    }

    // MARK: The cache, by modification date

    func setDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func theCacheReadsAgainOnlyWhenTheFileChanges() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        let file = work.accountFile
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com"}}"#, to: file)
        try setDate(first, of: file)
        var cache = ClaudeCodeAccountCache()
        #expect(cache.account(profile: work)?.email == "alex@example.com")
        // Same modification date: not parsed again.
        try write(#"{"oauthAccount":{"emailAddress":"sam@example.com"}}"#, to: file)
        try setDate(first, of: file)
        #expect(cache.account(profile: work)?.email == "alex@example.com")
        // A new login rewrites the file: seen at the next read.
        try setDate(first.addingTimeInterval(5), of: file)
        #expect(cache.account(profile: work)?.email == "sam@example.com")
        // Logged out: the entry is gone.
        try write(#"{"projects":{}}"#, to: file)
        try setDate(first.addingTimeInterval(10), of: file)
        #expect(cache.account(profile: work) == nil)
        // The file removed: nothing.
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com"}}"#, to: file)
        try setDate(first.addingTimeInterval(15), of: file)
        #expect(cache.account(profile: work)?.email == "alex@example.com")
        try FileManager.default.removeItem(at: file)
        #expect(cache.account(profile: work) == nil)
    }

    @Test func aFileCaughtHalfWrittenKeepsTheLastAccount() throws {
        let home = try TempHome(); defer { home.remove() }
        let work = try profile(home, ".claude-work")
        let file = work.accountFile
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        try write(#"{"oauthAccount":{"emailAddress":"alex@example.com"}}"#, to: file)
        try setDate(first, of: file)
        var cache = ClaudeCodeAccountCache()
        #expect(cache.account(profile: work)?.email == "alex@example.com")
        // Claude Code rewrites this file all the time: a read in the middle of a write keeps what was known.
        try write(#"{"oauthAccount":{"emailAdd"#, to: file)
        try setDate(first.addingTimeInterval(1), of: file)
        #expect(cache.account(profile: work)?.email == "alex@example.com")
        // Once the write is done, even with the same date, the next read sees it: a broken read is never cached.
        try write(#"{"oauthAccount":{"emailAddress":"sam@example.com"}}"#, to: file)
        try setDate(first.addingTimeInterval(1), of: file)
        #expect(cache.account(profile: work)?.email == "sam@example.com")
    }

    @Test func eachProfileHasItsOwnEntryInTheCache() throws {
        let home = try TempHome(); defer { home.remove() }
        let a = try profile(home, ".claude-a"), b = try profile(home, ".claude-b")
        try write(#"{"oauthAccount":{"emailAddress":"a@example.com"}}"#, to: a.accountFile)
        try write(#"{"oauthAccount":{"emailAddress":"b@example.com"}}"#, to: b.accountFile)
        var cache = ClaudeCodeAccountCache()
        #expect(cache.account(profile: a)?.email == "a@example.com")
        #expect(cache.account(profile: b)?.email == "b@example.com")
    }
}
