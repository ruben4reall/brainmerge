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
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return ProjectRegistry() }
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

    /// Name already assigned to this path on this machine.
    public func name(forPath path: String, machineID: String) -> String? {
        projects.first { $0.value.paths[machineID] == path }?.key
    }

    /// Finds or assigns a unique name. A name already known without a path on this machine is reused:
    /// it's the same project seen from another machine.
    public mutating func register(preferredName: String, path: String, machineID: String) -> String {
        if let existing = name(forPath: path, machineID: machineID) { return existing }
        var name = preferredName
        var n = 2
        while let entry = projects[name], entry.paths[machineID] != nil {
            name = "\(preferredName)-\(n)"
            n += 1
        }
        var entry = projects[name] ?? Entry(paths: [:])
        entry.paths[machineID] = path
        projects[name] = entry
        return name
    }
}
