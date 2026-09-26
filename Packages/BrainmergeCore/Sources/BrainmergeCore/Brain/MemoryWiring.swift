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
        var result = Result()
        var registry = try ProjectRegistry.load(brain.projectsFile)
        let before = registry
        for ref in try profile.projects() {
            let preferred = ref.path.map { ProjectSlug.projectName(forPath: $0, home: paths.home) }
                ?? ProjectSlug.projectName(forSlug: ref.slug, home: paths.home)
            let name = Self.knownName(slug: ref.slug, path: ref.path, in: registry, machineID: machineID)
                ?? registry.register(preferredName: preferred, path: Self.registryKey(ref), machineID: machineID)
            try link(profile.projectsDir.appending(path: ref.slug, directoryHint: .isDirectory), name: name,
                     identitySlug: identitySlug, into: &result)
        }
        try registry.save(to: brain.projectsFile)
        // These are the account's projects: its save carries the list, not "You edited".
        if registry != before { try? TouchedLedger(brain: brain, slug: identitySlug).append(".brainmerge/projects.json") }
        return result
    }

    /// The one project a session starts in (the SessionStart hook), whether or not `.claude.json` lists it yet: Claude Code's
    /// project folder is created when Claude Code has not made it, and a real memory folder is adopted like `wire` does.
    /// A project already linked into this memory, under any name, is left as it is and nothing is written.
    public func wireOne(projectPath: String, profile: CLIProfile, identitySlug: String) throws -> Result {
        var result = Result()
        guard projectPath.hasPrefix("/") else { return result }
        let slug = ProjectSlug.slug(forPath: projectPath)
        let projectDir = profile.projectsDir.appending(path: slug, directoryHint: .isDirectory)
        if isLinkedIntoThisMemory(projectDir.appending(path: "memory")) { return result }
        var registry = try ProjectRegistry.load(brain.projectsFile)
        let before = registry
        let name = Self.knownName(slug: slug, path: projectPath, in: registry, machineID: machineID)
            ?? registry.register(preferredName: ProjectSlug.projectName(forPath: projectPath, home: paths.home),
                                 path: projectPath, machineID: machineID)
        try link(projectDir, name: name, identitySlug: identitySlug, into: &result)
        try registry.save(to: brain.projectsFile)
        // The account's session added its project: the account's save carries the list, not "You edited".
        if registry != before { try? TouchedLedger(brain: brain, slug: identitySlug).append(".brainmerge/projects.json") }
        return result
    }

    /// Links `<projectDir>/memory` to the memory's folder for `name`.
    private func link(_ projectDir: URL, name: String, identitySlug: String, into result: inout Result) throws {
        let fm = FileManager.default
        let link = projectDir.appending(path: "memory")
        let target = brain.memoryDir(forProject: name)
        switch try Self.inspect(link, target: target) {
        case .linked:
            return
        case .external(let other):
            // Into another memory the app manages: relinked here, its notes left where they are.
            guard isInsideKnownMemory(other) else { result.external.append("\(name) -> \(other)"); return }
            try fm.removeItem(at: link)
        case .realDirectory:
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let adopted = try Self.adoptAll(from: link, into: target, suffix: identitySlug)
            result.conflicts += adopted.conflicts
            result.adopted.append(name)
            // The account's own notes, written before it shared this memory: its save commits them, not "You edited".
            let ledger = TouchedLedger(brain: brain, slug: identitySlug)
            for path in Self.files(adopted.moved, project: name) { try? ledger.append(path) }
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

    /// A link into a folder of this memory that exists, whatever the project's name there.
    func isLinkedIntoThisMemory(_ link: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let resolved = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        return resolved.path.hasPrefix(brain.memoryDir.standardizedFileURL.path + "/") && FileManager.default.fileExists(atPath: resolved.path)
    }

    public func status(profile: CLIProfile) throws -> [ProjectLinkStatus] {
        let registry = try ProjectRegistry.load(brain.projectsFile)
        return try profile.projects().map { ref in
            let preferred = ref.path.map { ProjectSlug.projectName(forPath: $0, home: paths.home) }
                ?? ProjectSlug.projectName(forSlug: ref.slug, home: paths.home)
            let name = Self.knownName(slug: ref.slug, path: ref.path, in: registry, machineID: machineID) ?? preferred
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

    /// The name a project already has on this machine, so it never becomes "name-2": by its path, by its sessions folder
    /// alone (wired before its path was known), or, when only the sessions folder is known, by a path registered for that
    /// same folder (a session start registers the path before `.claude.json` lists it).
    static func knownName(slug: String, path: String?, in registry: ProjectRegistry, machineID: String) -> String? {
        if let path, let name = registry.name(forPath: path, machineID: machineID) { return name }
        if let name = registry.name(forPath: registryKey(ProjectRef(slug: slug, path: nil)), machineID: machineID) { return name }
        guard path == nil else { return nil }
        return registry.projects.keys.sorted().first { name in
            guard let known = registry.projects[name]?.paths[machineID], known.hasPrefix("/") else { return false }
            return ProjectSlug.slug(forPath: known) == slug
        }
    }

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

    /// Moves the files from `from` into `into`. A duplicate keeps the brain's version; the other one is renamed
    /// `<name>.<suffix>.<ext>` (`<name>.<suffix>-2.<ext>` and so on when taken) and reported. An item identical to one
    /// already there (a copy the uninstaller left) stays out: it would only be a second copy. `moved`: where each item went.
    /// Moves everything out of a real memory folder, then removes the folder, only once it is empty: a note a session
    /// writes meanwhile is moved on the next pass, never deleted with the folder. Still not empty after a few passes (a
    /// session writing without pause), it stays, and this throws: the link waits for the next session start.
    static func adoptAll(from: URL, into: URL, suffix: String, afterPass: () -> Void = {}) throws -> (conflicts: [String], moved: [URL]) {
        let fm = FileManager.default
        var conflicts: [String] = [], moved: [URL] = []
        for _ in 0..<5 {
            let pass = try adopt(from: from, into: into, suffix: suffix)
            conflicts += pass.conflicts
            moved += pass.moved
            // What is left is identical to a note already in the memory: a copy, dropped.
            for item in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
                let twin = into.appending(path: item.lastPathComponent)
                if fm.contentsEqual(atPath: item.path, andPath: twin.path) { try fm.removeItem(at: item) }
            }
            afterPass()
            // Not recursive: a file that arrived since the listing makes it fail, and the next pass moves it.
            if rmdir(from.path) == 0 { return (conflicts, moved) }
            guard errno == ENOTEMPTY || errno == EEXIST else { break }
        }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: from.path,
                                                      NSLocalizedDescriptionKey: "\(from.path) kept changing while its notes moved to the memory"])
    }

    static func adopt(from: URL, into: URL, suffix: String) throws -> (conflicts: [String], moved: [URL]) {
        let fm = FileManager.default
        var conflicts: [String] = []
        var moved: [URL] = []
        for item in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
            var destination = into.appending(path: item.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                if fm.contentsEqual(atPath: item.path, andPath: destination.path) { continue }
                let base = item.deletingPathExtension().lastPathComponent
                let ext = item.pathExtension.isEmpty ? "" : ".\(item.pathExtension)"
                var n = 1
                repeat {
                    destination = into.appending(path: "\(base).\(suffix)\(n == 1 ? "" : "-\(n)")\(ext)")
                    n += 1
                } while fm.fileExists(atPath: destination.path) && !fm.contentsEqual(atPath: item.path, andPath: destination.path)
                if fm.fileExists(atPath: destination.path) { continue }
                conflicts.append(destination.lastPathComponent)
            }
            try fm.moveItem(at: item, to: destination)
            moved.append(destination)
        }
        return (conflicts, moved)
    }

    /// The files of these moved items, relative to the memory (`memory/<project>/…`), a folder's own files included.
    static func files(_ moved: [URL], project name: String) -> [String] {
        let fm = FileManager.default
        return moved.flatMap { item -> [String] in
            let base = "memory/\(name)/\(item.lastPathComponent)"
            // Not following a link: a linked folder is one entry for git, like a file.
            let type = (try? fm.attributesOfItem(atPath: item.path))?[.type] as? FileAttributeType
            guard type == .typeDirectory, let walk = fm.enumerator(atPath: item.path) else { return [base] }
            var found: [String] = []
            while let sub = walk.nextObject() as? String {
                if (walk.fileAttributes?[.type] as? FileAttributeType) != .typeDirectory { found.append("\(base)/\(sub)") }
            }
            return found
        }
    }
}
