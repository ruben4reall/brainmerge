import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Connections: MCP servers by name. Only keys are decoded: the values (commands, env, headers) can hold secrets.
@Suite struct MCPInventoryTests {
    static let secret = "SENTINEL_SECRET_VALUE"
    static let claudeJSON = """
    {"oauthAccount":{"emailAddress":"a@example.com"},
     "mcpServers":{"raylight":{"type":"http","url":"https://x","headers":{"Authorization":"\(secret)"}},"zeta":{"command":"z","env":{"DB_TOKEN":"\(secret)"}}},
     "projects":{"/p/one":{"mcpServers":{"playwright":{"command":"npx","args":["\(secret)"]}}},
                 "/p/two":{"mcpServers":{"playwright":{},"raylight":{}}},
                 "/p/three":{"allowedTools":[]}}}
    """
    static let desktopJSON = """
    {"mcpServers":{"Roblox_Studio":{"command":"x","env":{"KEY":"\(secret)"}}},"preferences":{"chromeExtension":{"pairedDeviceName":"\(secret)"}}}
    """

    @Test func readsClaudeCodeNamesOnly() {
        let names = MCPInventory.claudeCodeServers(Data(Self.claudeJSON.utf8))
        #expect(names.user == ["raylight", "zeta"])
        #expect(names.local == ["playwright", "raylight"])
        #expect(!"\(names)".contains("SENTINEL"))
    }

    @Test func readsDesktopNamesOnly() {
        let names = MCPInventory.desktopServers(Data(Self.desktopJSON.utf8))
        #expect(names == ["Roblox_Studio"])
        #expect(MCPInventory.desktopServers(Data("nope".utf8)).isEmpty)
    }

    @Test func readsAnAccountsFolders() throws {
        let home = try TempHome(); defer { home.remove() }
        let profile = home.url.appending(path: ".claude-work")
        let data = home.url.appending(path: "Claude-work")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data.appending(path: "Claude Extensions/ant.dir.pdf"), withIntermediateDirectories: true)
        try Data("file".utf8).write(to: data.appending(path: "Claude Extensions/stray.txt"))
        try Data(Self.claudeJSON.utf8).write(to: profile.appending(path: ".claude.json"))
        try Data(Self.desktopJSON.utf8).write(to: data.appending(path: "claude_desktop_config.json"))
        let inventory = MCPInventory.read(profile: CLIProfile(directory: profile), desktopData: data)
        #expect(inventory == MCPInventory(codeUser: ["raylight", "zeta"], codeLocal: ["playwright", "raylight"],
                                          desktop: ["Roblox_Studio"], extensions: ["ant.dir.pdf"]))
        #expect(MCPInventory.read(profile: nil, desktopData: nil).isEmpty)
    }

    @Test func marksWhatOnlyThisAccountHas() {
        let mine = MCPInventory(codeUser: ["raylight"], codeLocal: ["playwright"], desktop: ["Roblox"], extensions: [])
        let other = MCPInventory(codeUser: [], codeLocal: ["raylight"], desktop: [], extensions: ["pdf"])
        #expect(mine.onlyHere(comparedWith: [other]) == ["playwright", "Roblox"])
        #expect(mine.onlyHere(comparedWith: []) == [])
    }
}
