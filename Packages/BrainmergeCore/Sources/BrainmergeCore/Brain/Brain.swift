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

    @discardableResult
    public static func initialize(at root: URL, language: BrainLanguage, shell: Shell = Shell()) throws -> Brain {
        let brain = Brain(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: brain.memoryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: brain.brainMD.path) {
            try Data(BrainTemplates.brainMD(language).utf8).write(to: brain.brainMD, options: .atomic)
        }
        if !fm.fileExists(atPath: brain.gitignore.path) {
            try Data(".DS_Store\n.brainmerge/lock\n".utf8).write(to: brain.gitignore, options: .atomic)
        }
        for file in [brain.projectsFile, brain.identitiesFile] where !fm.fileExists(atPath: file.path) {
            try Data("{}\n".utf8).write(to: file, options: .atomic)
        }
        try BrainGit(brain: brain, shell: shell).initIfNeeded()
        return brain
    }
}
