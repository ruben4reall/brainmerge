import Foundation

/// `.brainmerge/projects.json`: a project's stable name and its path on each machine.
public struct ProjectRegistry: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var paths: [String: String]
        public init(paths: [String: String]) { self.paths = paths }
    }

    public var projects: [String: Entry]
    public init(projects: [String: Entry] = [:]) { self.projects = projects }

    public static func load(_ file: URL) throws -> ProjectRegistry {
        guard let data = try ExistingFile.read(file), !data.isEmpty else { return ProjectRegistry() }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], raw["projects"] == nil {
            return ProjectRegistry()
        }
        return try JSONDecoder().decode(ProjectRegistry.self, from: data)
    }

    public func save(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: file, options: .atomic)
    }

    /// Every path of this machine and its name, for many lookups at once. Where two names claim one path (a list
    /// edited by hand), the first in name order wins, as `name(forPath:machineID:)` would not promise either.
    public func names(machineID: String) -> [String: String] {
        var index: [String: String] = [:]
        for name in projects.keys.sorted() {
            if let path = projects[name]?.paths[machineID], index[path] == nil { index[path] = name }
        }
        return index
    }

    /// Name already assigned to this path on this machine.
    public func name(forPath path: String, machineID: String) -> String? {
        projects.first { $0.value.paths[machineID] == path }?.key
    }

    /// Finds or assigns a unique name. A name already known without a path on this machine is reused, with its spelling:
    /// it's the same project seen from another machine. Names are compared ignoring letter case: on a Mac's usual disk,
    /// `memory/Website` and `memory/website` are one folder.
    public mutating func register(preferredName: String, path: String, machineID: String) -> String {
        if let existing = name(forPath: path, machineID: machineID) { return existing }
        var name = preferredName
        var n = 2
        while let key = key(matching: name), projects[key]?.paths[machineID] != nil {
            name = "\(preferredName)-\(n)"
            n += 1
        }
        name = key(matching: name) ?? name
        var entry = projects[name] ?? Entry(paths: [:])
        entry.paths[machineID] = path
        projects[name] = entry
        return name
    }

    /// The name already in the registry that is this one, ignoring letter case; the exact spelling first.
    func key(matching name: String) -> String? {
        if projects[name] != nil { return name }
        return projects.keys.sorted().first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
