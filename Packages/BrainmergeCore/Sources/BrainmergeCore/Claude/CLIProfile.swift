import Foundation

/// A project as seen by a profile: its sessions folder (slug) and, when Claude Code knows it, its real path.
public struct ProjectRef: Equatable, Sendable {
    public let slug: String
    public let path: String?
    public init(slug: String, path: String?) { self.slug = slug; self.path = path }
}

/// A Claude Code configuration folder (the one CLAUDE_CONFIG_DIR points to).
public struct CLIProfile: Equatable, Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory.standardizedFileURL }

    public var settingsFile: URL { directory.appending(path: "settings.json") }
    public var claudeMD: URL { directory.appending(path: "CLAUDE.md") }
    public var projectsDir: URL { directory.appending(path: "projects", directoryHint: .isDirectory) }
    public var skillsDir: URL { directory.appending(path: "skills", directoryHint: .isDirectory) }
    public var exists: Bool { FileManager.default.fileExists(atPath: directory.path) }

    /// The `.claude.json` file that holds the projects. Under CLAUDE_CONFIG_DIR it lives inside the folder;
    /// for the default install (`~/.claude`) it lives next to it, in `~/.claude.json`, and the file
    /// inside the folder is just a stub with no `projects` key.
    public var claudeJSON: URL {
        let inside = directory.appending(path: ".claude.json")
        if Self.hasProjects(inside) { return inside }
        if directory.lastPathComponent == ".claude" {
            let beside = directory.deletingLastPathComponent().appending(path: ".claude.json")
            if FileManager.default.fileExists(atPath: beside.path) { return beside }
        }
        return inside
    }

    /// The `.claude.json` where Claude Code records the account it last used (read by `ClaudeCodeAccount`).
    /// Under CLAUDE_CONFIG_DIR it lives inside the folder. For the default install (`~/.claude`), Claude Code runs without
    /// CLAUDE_CONFIG_DIR and uses `~/.claude.json`, which wins over a stub inside the folder whenever it exists.
    /// Claude Code's legacy `.config.json` and its non-production file names are not looked for.
    public var accountFile: URL {
        let inside = directory.appending(path: ".claude.json")
        if directory.lastPathComponent == ".claude" {
            let beside = directory.deletingLastPathComponent().appending(path: ".claude.json")
            if FileManager.default.fileExists(atPath: beside.path) { return beside }
        }
        return inside
    }

    static func hasProjects(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let root = try? JSONDecoder().decode(ProjectKeys.self, from: data) else { return false }
        return !root.paths.isEmpty
    }

    /// The keys of "projects" in `.claude.json`, and nothing else: project settings can hold MCP servers and their secrets,
    /// so no value of the file is ever loaded.
    struct ProjectKeys: Decodable {
        enum Key: String, CodingKey { case projects }
        /// Any JSON value, skipped without being looked at.
        struct Skipped: Decodable { init(from decoder: Decoder) throws {} }
        let paths: [String]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            let projects = (try? container.decodeIfPresent([String: Skipped].self, forKey: .projects)) ?? nil
            paths = (projects ?? [:]).keys.sorted()
        }
    }

    /// Settings inherited from the primary. Never the hooks (they would fire twice) or the permissions.
    public static let inheritedKeys = ["language", "model", "theme", "effortLevel", "enabledPlugins"]

    /// Creates the folder if missing. A settings.json that's already present is never touched.
    @discardableResult
    public static func create(at directory: URL, inheritingFrom primary: CLIProfile?) throws -> CLIProfile {
        let fm = FileManager.default
        let profile = CLIProfile(directory: directory)
        try fm.createDirectory(at: profile.directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: profile.settingsFile.path) {
            var settings: [String: Any] = [:]
            if let primary, let data = try? Data(contentsOf: primary.settingsFile),
               let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in inheritedKeys { if let value = source[key] { settings[key] = value } }
            }
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: profile.settingsFile, options: .atomic)
        }
        try fm.createDirectory(at: profile.projectsDir, withIntermediateDirectories: true)
        if let primary, fm.fileExists(atPath: primary.skillsDir.path),
           !fm.fileExists(atPath: profile.skillsDir.path),
           (try? fm.destinationOfSymbolicLink(atPath: profile.skillsDir.path)) == nil {
            try fm.createSymbolicLink(at: profile.skillsDir, withDestinationURL: primary.skillsDir)
        }
        return profile
    }

    /// Real paths of the projects known to this profile: the keys of "projects" in .claude.json.
    public func projectPaths() throws -> [String] {
        let file = claudeJSON
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        guard let root = try? JSONDecoder().decode(ProjectKeys.self, from: data) else { throw BrainmergeError.invalidJSON(file.path) }
        return root.paths
    }

    /// All the projects: the known paths and the sessions folders, merged by slug.
    /// A folder with no known path keeps `path == nil`.
    public func projects() throws -> [ProjectRef] {
        var pathBySlug: [String: String] = [:]
        for path in try projectPaths() { pathBySlug[ProjectSlug.slug(forPath: path)] = path }
        var slugs = Set(pathBySlug.keys)
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: projectsDir.path) {
            for entry in entries where !entry.hasPrefix(".") { slugs.insert(entry) }
        }
        return slugs.sorted().map { ProjectRef(slug: $0, path: pathBySlug[$0]) }
    }
}
