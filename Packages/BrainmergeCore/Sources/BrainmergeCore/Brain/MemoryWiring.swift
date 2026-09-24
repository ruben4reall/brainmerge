import Foundation

public enum ProjectLinkState: Equatable, Sendable {
    case linked
    case missing
    case realDirectory
    case external(String)
    case broken
}

public struct ProjectLinkStatus: Equatable, Sendable {
    public let name: String
    public let path: String
    public let slug: String
    public let state: ProjectLinkState
}

/// Replaces each project's `projects/<slug>/memory` with a link to `Brain/memory/<project>/`.
public struct MemoryWiring: Sendable {
    public let brain: Brain
    public let paths: Paths
    public let machineID: String
    /// The other memories the app manages: a link into one of them is moved to this brain (the notes stay there).
    public let knownRoots: [URL]

    public init(brain: Brain, paths: Paths, machineID: String, knownRoots: [URL] = []) {
        self.brain = brain; self.paths = paths; self.machineID = machineID; self.knownRoots = knownRoots
    }

    public struct Result: Equatable, Sendable {
        public var linked: [String] = []
        public var adopted: [String] = []
        public var conflicts: [String] = []
        public var external: [String] = []
        public init() {}
    }

    public func wire(profile: CLIProfile, identitySlug: String) throws -> Result {
        let fm = FileManager.default
        var result = Result()
        var registry = try ProjectRegistry.load(brain.projectsFile)
        for ref in try profile.projects() {
            let preferred = ref.path.map { ProjectSlug.projectName(forPath: $0, home: paths.home) }
                ?? ProjectSlug.projectName(forSlug: ref.slug, home: paths.home)
            let name = registry.register(preferredName: preferred, path: Self.registryKey(ref), machineID: machineID)
            let projectDir = profile.projectsDir.appending(path: ref.slug, directoryHint: .isDirectory)
            let link = projectDir.appending(path: "memory")
            let target = brain.memoryDir(forProject: name)
            switch try Self.inspect(link, target: target) {
            case .linked:
                continue
            case .external(let other):
                // Into another memory the app manages: relinked here, its notes left where they are.
                guard isInsideKnownMemory(other) else { result.external.append("\(name) -> \(other)"); continue }
                try fm.removeItem(at: link)
            case .realDirectory:
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                result.conflicts += try Self.adopt(from: link, into: target, suffix: identitySlug)
                result.adopted.append(name)
                try fm.removeItem(at: link)
            case .broken:
                try fm.removeItem(at: link)
            case .missing:
                break
            }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
            result.linked.append(name)
        }
        try registry.save(to: brain.projectsFile)
        return result
    }

    public func status(profile: CLIProfile) throws -> [ProjectLinkStatus] {
        let registry = try ProjectRegistry.load(brain.projectsFile)
        return try profile.projects().map { ref in
            let preferred = ref.path.map { ProjectSlug.projectName(forPath: $0, home: paths.home) }
                ?? ProjectSlug.projectName(forSlug: ref.slug, home: paths.home)
            let name = registry.name(forPath: Self.registryKey(ref), machineID: machineID) ?? preferred
            let link = profile.projectsDir.appending(path: ref.slug, directoryHint: .isDirectory).appending(path: "memory")
            return ProjectLinkStatus(name: name, path: ref.path ?? ref.slug, slug: ref.slug,
                                     state: try Self.inspect(link, target: brain.memoryDir(forProject: name)))
        }
    }

    func isInsideKnownMemory(_ path: String) -> Bool {
        knownRoots.contains { root in
            let memory = Brain(root: root).memoryDir.standardizedFileURL.path
            return memory != brain.memoryDir.standardizedFileURL.path && path.hasPrefix(memory + "/")
        }
    }

    /// Registry key: the real path, or the slug when Claude Code only knows the sessions folder.
    static func registryKey(_ ref: ProjectRef) -> String { ref.path ?? "slug:\(ref.slug)" }

    /// `attributesOfItem` doesn't follow links: we see the link itself.
    static func inspect(_ link: URL, target: URL) throws -> ProjectLinkState {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: link.path) else { return .missing }
        guard (attributes[.type] as? FileAttributeType) == .typeSymbolicLink else { return .realDirectory }
        let destination = try fm.destinationOfSymbolicLink(atPath: link.path)
        let resolved = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        if resolved.path == target.standardizedFileURL.path { return .linked }
        return fm.fileExists(atPath: resolved.path) ? .external(resolved.path) : .broken
    }

    /// Moves the files from `from` into `into`. A duplicate keeps the brain's version;
    /// the other one is renamed `<name>.<suffix>.<ext>` and reported.
    static func adopt(from: URL, into: URL, suffix: String) throws -> [String] {
        let fm = FileManager.default
        var conflicts: [String] = []
        for item in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
            var destination = into.appending(path: item.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                let base = item.deletingPathExtension().lastPathComponent
                let ext = item.pathExtension.isEmpty ? "" : ".\(item.pathExtension)"
                destination = into.appending(path: "\(base).\(suffix)\(ext)")
                conflicts.append(destination.lastPathComponent)
            }
            try fm.moveItem(at: item, to: destination)
        }
        return conflicts
    }
}
