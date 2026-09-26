import Foundation

/// The shared folder. Brainmerge creates what's missing there, never rewrites what exists, and never renames anything.
public struct Brain: Equatable, Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }

    public var brainMD: URL { root.appending(path: "BRAIN.md") }
    public var memoryDir: URL { root.appending(path: "memory", directoryHint: .isDirectory) }
    public var metaDir: URL { root.appending(path: ".brainmerge", directoryHint: .isDirectory) }
    public var projectsFile: URL { metaDir.appending(path: "projects.json") }
    public var identitiesFile: URL { metaDir.appending(path: "identities.json") }
    public var lockFile: URL { metaDir.appending(path: "lock") }
    /// The digests of lines you said are not secrets (see NotSecrets): saved in the memory like your own edits.
    public var notSecretsFile: URL { metaDir.appending(path: "not-secrets.json") }
    /// Where each account lists what it wrote until its next save (see TouchedLedger). Never committed.
    public var touchedDir: URL { metaDir.appending(path: "touched", directoryHint: .isDirectory) }
    public var gitignore: URL { root.appending(path: ".gitignore") }
    public var gitDir: URL { root.appending(path: ".git", directoryHint: .isDirectory) }

    public var exists: Bool { FileManager.default.fileExists(atPath: root.path) }
    public var isInitialized: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: brainMD.path) && fm.fileExists(atPath: gitDir.path) && fm.fileExists(atPath: memoryDir.path)
    }

    public func memoryDir(forProject name: String) -> URL {
        memoryDir.appending(path: name, directoryHint: .isDirectory)
    }

    /// The memory's own files: the only ones the person's edits are ever committed from (see OwnEdits). An Obsidian vault's
    /// settings, daily notes or anything else in the folder are never added.
    public static let ownEditsScope = ["memory", "BRAIN.md", ".brainmerge/projects.json", ".brainmerge/identities.json",
                                       ".brainmerge/not-secrets.json", ".gitignore"]

    /// What a memory's .gitignore must hold: Finder's files, the lock, and the accounts' lists of what they wrote.
    static let ignoredLines = [".DS_Store", ".brainmerge/lock", ".brainmerge/touched/"]

    /// Appends to .gitignore the lines it lacks, never changing what is there (an older memory, or one the person edits).
    public func ensureIgnores() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: gitignore.path) else {
            try Data(Self.ignoredLines.map { $0 + "\n" }.joined().utf8).write(to: gitignore, options: .atomic)
            return
        }
        let text = try String(contentsOf: gitignore, encoding: .utf8)
        let present = Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = Self.ignoredLines.filter { line in !present.contains(line) && !(line.hasSuffix("/") && present.contains(String(line.dropLast()))) }
        guard !missing.isEmpty else { return }
        let lead = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        let handle = try FileHandle(forWritingTo: gitignore)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lead + missing.map { $0 + "\n" }.joined()).utf8))
    }

    /// Where a folder really is, links resolved, even when its last parts do not exist yet (a new folder to create).
    static func resolved(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        return rest.reduce(existing.resolvingSymlinksInPath()) { $0.appending(path: $1) }
    }

    /// The top folder of the git repository `folder` would sit inside, if any: a memory made there would be a second
    /// repository inside it, whose notes the outer one's backups stop covering. Looked for from the folder's parent up, where
    /// the folder really is (links resolved), without starting git. The folder's own `.git` is not another repository.
    public static func enclosingRepository(of folder: URL) -> URL? {
        let fm = FileManager.default
        var current = resolved(folder).deletingLastPathComponent()
        while true {
            if fm.fileExists(atPath: current.appending(path: ".git").path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == "/" { return nil }
            current = parent
        }
    }

    @discardableResult
    public static func initialize(at root: URL, language: BrainLanguage, shell: Shell = Shell(),
                                  availability: GitAvailability = .shared) throws -> Brain {
        let brain = Brain(root: root)
        let fm = FileManager.default
        if !fm.fileExists(atPath: brain.gitDir.path) {
            // Nothing is created half way: without git the memory could not keep its history.
            if !availability.isAvailable { throw BrainmergeError.gitUnavailable }
            // A second repository inside another one would take its notes out of that one's backups.
            if let top = enclosingRepository(of: brain.root) { throw BrainmergeError.memoryInsideRepository(top.path) }
        }
        try fm.createDirectory(at: brain.memoryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: brain.brainMD.path) {
            try Data(BrainTemplates.brainMD(language).utf8).write(to: brain.brainMD, options: .atomic)
        }
        try brain.ensureIgnores()
        for file in [brain.projectsFile, brain.identitiesFile] where !fm.fileExists(atPath: file.path) {
            try Data("{}\n".utf8).write(to: file, options: .atomic)
        }
        try BrainGit(brain: brain, shell: shell, availability: availability).initIfNeeded()
        return brain
    }
}
