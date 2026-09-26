import Foundation

/// A save guarded against keys: stages the paths, reads the lines it adds (SecretGuard), leaves out the files that look
/// like they hold a key, commits the rest, and records what it held (HeldStore). Shared by the accounts' saves and yours.
struct GuardedCommit {
    let brain: Brain
    let git: BrainGit
    let held: HeldStore

    struct Outcome: Equatable, Sendable {
        var saved: [String] = []
        var held: [HeldNote] = []
    }

    func run(paths: [String], author: BrainGit.Author, account: String?, message: ([String]) -> String) throws -> Outcome {
        var notes = held.load()
        let allowlist = NotSecrets.hashes(in: brain)
        var found: [HeldNote] = []
        var staged: [String] = []
        let saved = try git.commit(paths: paths, author: author, hold: { changes in
            staged = changes.paths
            let findings = SecretGuard.scan(diff: try changes.addedLines()) { path, hash in
                allowlist.contains(hash.hex) || notes.allows(account: account, path: path, hash: hash)
            }
            found = findings.map { HeldNote(account: account, path: $0.path, line: $0.line, shape: $0.shape, hash: $0.hash) }
            return Set(found.map(\.path))
        }, message: message)
        let before = notes
        notes.record(account: account, requested: Set(paths), staged: Set(staged), found: found)
        if notes != before { try held.save(notes) }
        return Outcome(saved: saved, held: found)
    }
}

/// An account's save when its turn ends (the Stop hook): exactly the paths it wrote, taken from its list, committed under
/// its name with the words of MemorySentence, minus the notes the secret guard holds back, which stay on its list for its
/// next save. Run under the memory's lock.
public struct AccountSave: Sendable {
    public let brain: Brain
    public let git: BrainGit
    public let held: HeldStore
    public init(brain: Brain, git: BrainGit, held: HeldStore) { self.brain = brain; self.git = git; self.held = held }

    public struct Outcome: Equatable, Sendable {
        /// The paths committed, sorted.
        public var saved: [String] = []
        /// The notes held back: never the line, see HeldNote.
        public var held: [HeldNote] = []
    }

    /// When the commit fails, every path goes back on the list for the next save.
    @discardableResult
    public func run(for identity: Identity) throws -> Outcome {
        let ledger = TouchedLedger(brain: brain, slug: identity.slug)
        let paths = try ledger.take()
        guard !paths.isEmpty else {
            // Nothing to save, but git's index may still be behind an earlier save (see BrainGit.catchUpIndex).
            try? git.catchUpIndex()
            try ledger.finish(keeping: [])
            return Outcome()
        }
        do {
            let result = try GuardedCommit(brain: brain, git: git, held: held)
                .run(paths: paths, author: identity.gitAuthor, account: identity.slug) { MemorySentence.message(name: identity.name, files: $0) }
            try ledger.finish(keeping: Array(Set(result.held.map(\.path))).sorted())
            return Outcome(saved: result.saved, held: result.held)
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
    public let held: HeldStore
    public init(brain: Brain, git: BrainGit, held: HeldStore) { self.brain = brain; self.git = git; self.held = held }

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
        // The real index catches up with an account's save first, session or not: a plain commit of yours never undoes it.
        try? git.catchUpIndex()
        if sessionRunning { return .sessionRunning }
        let paths = try pending()
        guard !paths.isEmpty else { return .nothing }
        if let newest = newestChange(of: paths), now.timeIntervalSince(newest) < Self.quietPeriod { return .tooRecent }
        // Guarded like an account's save: a note that looks like it holds a key waits, with the others saved.
        let result = try GuardedCommit(brain: brain, git: git, held: held)
            .run(paths: paths, author: Self.author, account: nil) { MemorySentence.message(name: Self.author.name, files: $0, byYou: true) }
        return result.saved.isEmpty ? .nothing : .saved(result.saved)
    }

    /// When the latest of these changes happened: a file's modification date, or for a file that is gone, that of the
    /// nearest folder still there (removing a file changes its folder).
    public func newestChange(of paths: [String]) -> Date? { Self.newestChange(of: paths, in: brain) }

    /// The same, for any memory (the Tidy tab asks it of each change not saved).
    public static func newestChange(of paths: [String], in brain: Brain) -> Date? {
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
