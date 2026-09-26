import Foundation

/// An account's save when its turn ends (the Stop hook): exactly the paths it wrote, taken from its list, committed under
/// its name with the words of MemorySentence. Run under the memory's lock.
public struct AccountSave: Sendable {
    public let brain: Brain
    public let git: BrainGit
    public init(brain: Brain, git: BrainGit) { self.brain = brain; self.git = git }

    /// The paths committed, sorted. When the commit fails, every path goes back on the list for the next save.
    @discardableResult
    public func run(for identity: Identity) throws -> [String] {
        let ledger = TouchedLedger(brain: brain, slug: identity.slug)
        let paths = try ledger.take()
        guard !paths.isEmpty else { try ledger.finish(keeping: []); return [] }
        do {
            let saved = try git.commit(paths: paths, author: identity.gitAuthor) { MemorySentence.message(name: identity.name, files: $0) }
            try ledger.finish(keeping: [])
            return saved
        } catch {
            try? ledger.finish(keeping: paths)
            throw error
        }
    }
}

/// The person's own edits to the notes, outside Claude: saved as You, never by a hook. Only the memory's own files are
/// looked at (Brain.ownEditsScope), minus every path an account wrote and has not saved yet. A change is saved once
/// nothing moved for ten minutes and no Claude Code session runs, so a note Claude wrote without an edit tool (a shell
/// command) is not quickly taken for the person's.
public struct OwnEdits: Sendable {
    public static let author = BrainGit.Author(name: "You", email: "outside.claude@brainmerge.local")
    public static let quietPeriod: TimeInterval = 600

    public let brain: Brain
    public let git: BrainGit
    public init(brain: Brain, git: BrainGit) { self.brain = brain; self.git = git }

    public enum Outcome: Equatable, Sendable {
        case nothing, tooRecent, sessionRunning
        case saved([String])
    }

    /// The changes no account claims.
    public func pending() throws -> [String] {
        let claimed = TouchedLedger.claimed(in: brain)
        return try git.status(scope: Brain.ownEditsScope).filter { !claimed.contains($0) }
    }

    /// Run under the memory's lock. `sessionRunning`: a Claude Code session of any account is running now.
    public func save(now: Date, sessionRunning: Bool) throws -> Outcome {
        if sessionRunning { return .sessionRunning }
        let paths = try pending()
        guard !paths.isEmpty else { return .nothing }
        if let newest = newestChange(of: paths), now.timeIntervalSince(newest) < Self.quietPeriod { return .tooRecent }
        let saved = try git.commit(paths: paths, author: Self.author) { MemorySentence.message(name: Self.author.name, files: $0, byYou: true) }
        return saved.isEmpty ? .nothing : .saved(saved)
    }

    /// When the latest of these changes happened: a file's modification date, or for a file that is gone, that of the
    /// nearest folder still there (removing a file changes its folder).
    public func newestChange(of paths: [String]) -> Date? {
        let fm = FileManager.default
        let root = brain.root.standardizedFileURL.path
        return paths.compactMap { path -> Date? in
            var url = brain.root.appending(path: path)
            while true {
                if let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date { return date }
                let parent = url.deletingLastPathComponent()
                guard parent.standardizedFileURL.path.hasPrefix(root), parent.path != url.path else { return nil }
                url = parent
            }
        }.max()
    }
}

public extension Identity {
    /// The author of this account's saves: its name, and an address made from its slug that only means something here.
    var gitAuthor: BrainGit.Author { BrainGit.Author(name: name, email: gitAuthorEmail) }
}
