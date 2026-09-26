import Foundation

/// An account's MCP servers by name: Claude Code's user scope and local (per project) scope from its `.claude.json`,
/// the Claude app's `claude_desktop_config.json` servers and its Desktop Extensions folders. Only key names are decoded:
/// the values (commands, arguments, environment, headers) can hold secrets and are never loaded.
public struct MCPInventory: Equatable, Sendable {
    public var codeUser: [String]
    public var codeLocal: [String]
    public var desktop: [String]
    public var extensions: [String]

    public init(codeUser: [String] = [], codeLocal: [String] = [], desktop: [String] = [], extensions: [String] = []) {
        self.codeUser = codeUser; self.codeLocal = codeLocal; self.desktop = desktop; self.extensions = extensions
    }

    public var isEmpty: Bool { codeUser.isEmpty && codeLocal.isEmpty && desktop.isEmpty && extensions.isEmpty }
    public var names: Set<String> { Set(codeUser + codeLocal + desktop + extensions) }

    /// The names this account has that none of the others has; nothing when there is no other account to compare with.
    public func onlyHere(comparedWith others: [MCPInventory]) -> Set<String> {
        guard !others.isEmpty else { return [] }
        return names.subtracting(others.reduce(into: Set<String>()) { $0.formUnion($1.names) })
    }

    public static func read(profile: CLIProfile?, desktopData: URL?) -> MCPInventory {
        var inventory = MCPInventory()
        if let profile, let data = try? Data(contentsOf: profile.accountFile) {
            (inventory.codeUser, inventory.codeLocal) = claudeCodeServers(data)
        }
        if let desktopData {
            if let data = try? Data(contentsOf: desktopData.appending(path: "claude_desktop_config.json")) {
                inventory.desktop = desktopServers(data)
            }
            let folder = desktopData.appending(path: "Claude Extensions", directoryHint: .isDirectory)
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                       options: .skipsHiddenFiles)) ?? []
            inventory.extensions = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(\.lastPathComponent).sorted()
        }
        return inventory
    }

    /// User scope (top-level `mcpServers`) and local scope (each project's `mcpServers`), names sorted and once each.
    static func claudeCodeServers(_ data: Data) -> (user: [String], local: [String]) {
        guard let root = try? JSONDecoder().decode(CodeRoot.self, from: data) else { return ([], []) }
        return (root.user.sorted(), Array(Set(root.local)).sorted())
    }

    static func desktopServers(_ data: Data) -> [String] {
        ((try? JSONDecoder().decode(Servers.self, from: data))?.names ?? []).sorted()
    }

    private struct NameKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
    /// The keys of an object, its values never looked at.
    private struct KeyNames: Decodable {
        let names: [String]
        init(from decoder: Decoder) throws { names = try decoder.container(keyedBy: NameKey.self).allKeys.map(\.stringValue) }
    }
    /// An object's `mcpServers` names, nothing else of it.
    private struct Servers: Decodable {
        enum Key: String, CodingKey { case mcpServers }
        let names: [String]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            names = (try? container.decodeIfPresent(KeyNames.self, forKey: .mcpServers))?.names ?? []
        }
    }
    private struct CodeRoot: Decodable {
        enum Key: String, CodingKey { case mcpServers, projects }
        let user: [String]
        let local: [String]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            user = (try? container.decodeIfPresent(KeyNames.self, forKey: .mcpServers))?.names ?? []
            guard let projects = try? container.nestedContainer(keyedBy: NameKey.self, forKey: .projects) else { local = []; return }
            local = projects.allKeys.flatMap { (try? projects.decode(Servers.self, forKey: $0))?.names ?? [] }
        }
    }
}
