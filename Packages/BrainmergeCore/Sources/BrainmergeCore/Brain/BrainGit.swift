import Foundation

public struct BrainGit: Sendable {
    public let brain: Brain
    public let shell: Shell
    public init(brain: Brain, shell: Shell = Shell()) { self.brain = brain; self.shell = shell }

    public struct Entry: Equatable, Sendable {
        public let hash: String
        public let date: Date
        public let authorName: String
        public let authorEmail: String
        public let message: String
        public let files: [String]
        public init(hash: String, date: Date, authorName: String, authorEmail: String, message: String, files: [String]) {
            self.hash = hash; self.date = date; self.authorName = authorName; self.authorEmail = authorEmail; self.message = message; self.files = files
        }
    }

    public func initIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: brain.gitDir.path) else { return }
        try shell.check("/usr/bin/git", ["init", "-q", "-b", "main"], cwd: brain.root)
    }

    public func hasChanges() throws -> Bool {
        !(try shell.check("/usr/bin/git", ["status", "--porcelain"], cwd: brain.root)).isEmpty
    }

    /// Adds everything and commits under the identity's name. Returns false if there was nothing to commit.
    @discardableResult
    public func commitAll(authorName: String, authorEmail: String, message: String) throws -> Bool {
        try shell.check("/usr/bin/git", ["add", "-A"], cwd: brain.root)
        guard try hasChanges() else { return false }
        try shell.check("/usr/bin/git", ["-c", "user.name=\(authorName)", "-c", "user.email=\(authorEmail)",
                                         "commit", "-q", "-m", message], cwd: brain.root)
        return true
    }

    public func log(limit: Int = 50) throws -> [Entry] {
        guard try shell.run("/usr/bin/git", ["rev-parse", "--verify", "HEAD"], cwd: brain.root).status == 0 else { return [] }
        let out = try shell.check("/usr/bin/git", ["log", "-n", "\(limit)", "--name-only",
                                                   "--pretty=format:%x1e%H%x1f%aI%x1f%an%x1f%ae%x1f%s"], cwd: brain.root)
        let iso = ISO8601DateFormatter()
        return out.split(separator: "\u{1e}").compactMap { record -> Entry? in
            let lines = record.split(separator: "\n", omittingEmptySubsequences: false)
            guard let header = lines.first else { return nil }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, let date = iso.date(from: fields[1]) else { return nil }
            let files = lines.dropFirst().map(String.init).filter { !$0.isEmpty }
            return Entry(hash: fields[0], date: date, authorName: fields[2], authorEmail: fields[3], message: fields[4], files: files)
        }
    }

    /// Who last saved each file, from the most recent commits: path to author name, email and date.
    public func lastAuthors(limit: Int = 2000) throws -> [String: (name: String, email: String, date: Date)] {
        var authors: [String: (name: String, email: String, date: Date)] = [:]
        for entry in try log(limit: limit) {
            for file in entry.files where authors[file] == nil { authors[file] = (entry.authorName, entry.authorEmail, entry.date) }
        }
        return authors
    }

    /// Exclusive lock on `.brainmerge/lock`: two hooks never commit at the same time.
    public func withLock<T>(timeout: TimeInterval, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
        let fd = open(brain.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw BrainmergeError.lockTimeout }
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if Date() >= deadline { throw BrainmergeError.lockTimeout }
            usleep(100_000)
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
