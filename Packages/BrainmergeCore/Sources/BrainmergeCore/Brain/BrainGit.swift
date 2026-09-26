import Foundation

public struct BrainGit: Sendable {
    public let brain: Brain
    public let shell: Shell
    public let availability: GitAvailability
    public init(brain: Brain, shell: Shell = Shell(), availability: GitAvailability = .shared) {
        self.brain = brain; self.shell = shell; self.availability = availability
    }

    /// Every entry point that would start git checks first: without Apple's tools, /usr/bin/git pops a dialog.
    private func requireGit() throws { guard availability.isAvailable else { throw BrainmergeError.gitUnavailable } }

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
        try requireGit()
        try shell.check("/usr/bin/git", ["init", "-q", "-b", "main"], cwd: brain.root)
    }

    public func hasChanges() throws -> Bool {
        try requireGit()
        return !(try shell.check("/usr/bin/git", ["status", "--porcelain"], cwd: brain.root)).isEmpty
    }

    /// Who a commit is by: an account, or the person themselves (see OwnEdits).
    public struct Author: Equatable, Sendable {
        public let name: String
        public let email: String
        public init(name: String, email: String) { self.name = name; self.email = email }
    }

    /// The changed paths, relative to the memory, under `scope`: modified, added, deleted, and every file of a new folder.
    /// What .gitignore leaves out never shows. Names are taken literally, never as patterns.
    public func status(scope: [String]) throws -> [String] {
        try requireGit()
        guard !scope.isEmpty else { return [] }
        let out = try shell.check("/usr/bin/git", ["--literal-pathspecs", "status", "--porcelain=v1", "-z", "--untracked-files=all", "--"] + scope,
                                  cwd: brain.root)
        return Self.statusPaths(out)
    }

    /// `XY path`, NUL separated; a rename or a copy is followed by its old path, which changed too.
    static func statusPaths(_ out: String) -> [String] {
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var paths: [String] = []
        var index = 0
        while index < fields.count {
            let entry = fields[index]
            index += 1
            guard entry.count > 3 else { continue }
            paths.append(String(entry.dropFirst(3)))
            let code = entry.prefix(2)
            if code.contains("R") || code.contains("C"), index < fields.count { paths.append(fields[index]); index += 1 }
        }
        return paths
    }

    /// A save's paths once staged, in the save's own index: what `addedLines()` reads there is exactly what the commit
    /// holds.
    public struct Staged: Sendable {
        /// The paths whose staged content differs from the last commit, sorted.
        public let paths: [String]
        let git: BrainGit
        let index: URL
        /// What staging these paths adds, and only that (see `diffCachedAdded`).
        public func addedLines() throws -> String { try git.diffCachedAdded(paths: paths, index: index) }
    }

    /// Commits exactly these paths, those of them that changed, under `author`, and nothing else. The save works in an
    /// index of its own, made from the last commit: what the person staged by hand stays staged, other files stay as
    /// they are, and the commit holds what was staged, never what a session writes meanwhile (it waits for the next
    /// save). Once the paths are staged, `hold` reads them and names those to leave out (the secret guard); a name that
    /// is not one of them fails the save, since it cannot tell which note was meant. Returns the paths committed, sorted;
    /// none when nothing changed or everything was held.
    @discardableResult
    public func commit(paths: [String], author: Author, hold: (Staged) throws -> Set<String> = { _ in [] },
                       message: ([String]) -> String) throws -> [String] {
        try requireGit()
        let wanted = Set(paths)
        guard !wanted.isEmpty else { return [] }
        // A plain commit would finish the person's own merge or pick under this author: the save waits for them instead.
        guard !(try operationUnfinished()) else { throw BrainmergeError.gitOperationUnfinished }
        try? catchUpIndex()
        let changed = Set(try status(scope: Array(wanted))).intersection(wanted).sorted()
        guard !changed.isEmpty else { return [] }
        let fm = FileManager.default
        let index = fm.temporaryDirectory.appending(path: "brainmerge-save-\(UUID().uuidString).index")
        defer { try? fm.removeItem(at: index) }
        let env = ["GIT_INDEX_FILE": index.path]
        if head() != nil {
            // A copy of the real index keeps its file dates, so no note is read again; a reset by path takes it back to
            // the last commit without moving HEAD's history (a bare reset would log a move and set ORIG_HEAD).
            let real = brain.gitDir.appending(path: "index")
            if fm.fileExists(atPath: real.path) { try fm.copyItem(at: real, to: index) }
            try shell.check("/usr/bin/git", ["reset", "-q", "--", "."], cwd: brain.root, environment: env)
        }
        try shell.check("/usr/bin/git", ["--literal-pathspecs", "add", "-A", "--"] + changed, cwd: brain.root, environment: env)
        let staged = try shell.check("/usr/bin/git", ["--literal-pathspecs", "diff", "--cached", "--name-only", "-z", "--no-renames", "--"] + changed,
                                     cwd: brain.root, environment: env)
            .split(separator: "\0").map(String.init).sorted()
        let held = try hold(Staged(paths: staged, git: self, index: index))
        guard held.isSubset(of: staged) else { throw BrainmergeError.heldFileUnknown }
        let kept = staged.filter { !held.contains($0) }
        guard !kept.isEmpty else { return [] }
        if !held.isEmpty { try unstage(staged.filter(held.contains), index: index) }
        try shell.check("/usr/bin/git", ["-c", "user.name=\(author.name)", "-c", "user.email=\(author.email)", "commit", "-q", "-m", message(kept)],
                        cwd: brain.root, environment: env)
        followCommit(kept)
        return kept
    }

    /// The person's own git is stopped half way in this memory: a merge, a cherry-pick, a revert, a rebase or a bisect not
    /// finished, or conflicts left in the index (a stash pop leaves no other trace). A commit then would record their
    /// merge in an account's name, sign a save with the picked commit's author, or keep conflict markers.
    public func operationUnfinished() throws -> Bool {
        try requireGit()
        let markers = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "REBASE_HEAD", "rebase-merge", "rebase-apply", "BISECT_LOG"]
        // Asked of git, not guessed: a worktree or a separate git folder keeps these elsewhere.
        let located = try shell.check("/usr/bin/git", ["rev-parse"] + markers.flatMap { ["--git-path", $0] }, cwd: brain.root)
        let fm = FileManager.default
        // Git answers relative to the memory's folder: appended to it, never resolved against a URL whose folder may
        // lack its trailing slash (that would look in the parent folder and miss the merge).
        let stopped = located.split(separator: "\n").contains { line in
            let path = String(line)
            return fm.fileExists(atPath: path.hasPrefix("/") ? path : brain.root.appending(path: path).path)
        }
        if stopped { return true }
        return !(try shell.check("/usr/bin/git", ["ls-files", "-u"], cwd: brain.root)).isEmpty
    }

    /// Where the paths a save could not bring the real index up to are kept: in the git folder, never committed.
    var indexBehindFile: URL { brain.gitDir.appending(path: "brainmerge-index-behind") }

    /// The paths saved while another git held the real index: it still has their content from before the save, which a
    /// plain `git commit` of the person's would put back. Caught up by the next save or the app's minute pass.
    public var indexBehind: [String] {
        guard let data = try? Data(contentsOf: indexBehindFile) else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init).sorted()
    }

    /// The real index follows a save's commit for these paths, so a note rewritten since shows as changed. Another git
    /// (an editor's, Obsidian Git's status check) may hold the index for a moment: tried again for half a second, then
    /// left to `catchUpIndex`, never failing a save whose commit is made.
    func followCommit(_ paths: [String]) {
        for attempt in 0..<10 {
            let result = try? shell.run("/usr/bin/git", ["--literal-pathspecs", "reset", "-q", "--"] + paths, cwd: brain.root)
            if result?.status == 0 { return }
            // Git names the lock it could not take (in any language): the lock may be gone already, so ask its words.
            guard attempt < 9, result?.stderr.contains("index.lock") == true else { break }
            usleep(50_000)
        }
        let behind = Set(indexBehind).union(paths).sorted()
        try? Data(behind.joined(separator: "\0").utf8).write(to: indexBehindFile, options: .atomic)
    }

    /// Brings the real index up to the last commit for the paths a save left behind, those still behind only: another
    /// path you staged yourself stays staged. Waits while your own merge or pick is stopped, where a reset would drop
    /// its conflicts.
    public func catchUpIndex() throws {
        let behind = indexBehind
        guard !behind.isEmpty, !(try operationUnfinished()) else { return }
        let stale = try shell.check("/usr/bin/git", ["--literal-pathspecs", "diff", "--cached", "--name-only", "-z", "--no-renames", "--"] + behind,
                                    cwd: brain.root)
            .split(separator: "\0").map(String.init)
        if !stale.isEmpty { try shell.check("/usr/bin/git", ["--literal-pathspecs", "reset", "-q", "--"] + stale, cwd: brain.root) }
        try FileManager.default.removeItem(at: indexBehindFile)
    }

    /// What staging these paths adds, and only that: no context line, no line saved before, no rename detection, and none
    /// of the person's diff settings (an external diff, a text conversion, other prefixes). Always as text: a `-diff`
    /// attribute or a NUL byte never hides a line. `index`: a save's own index instead of the real one.
    public func diffCachedAdded(paths: [String], index: URL? = nil) throws -> String {
        try requireGit()
        guard !paths.isEmpty else { return "" }
        return try shell.check("/usr/bin/git", ["--literal-pathspecs", "-c", "core.quotePath=false", "diff", "--cached", "-U0", "--no-color", "--text",
                                                "--no-ext-diff", "--no-textconv", "--no-renames", "--src-prefix=a/", "--dst-prefix=b/", "--"] + paths,
                               cwd: brain.root, environment: index.map { ["GIT_INDEX_FILE": $0.path] })
    }

    /// Takes these paths out of the index again, the index only: the notes on disk and the history do not move.
    /// `index`: a save's own index instead of the real one.
    public func unstage(_ paths: [String], index: URL? = nil) throws {
        try requireGit()
        guard !paths.isEmpty else { return }
        let env = index.map { ["GIT_INDEX_FILE": $0.path] }
        if head() != nil {
            try shell.check("/usr/bin/git", ["--literal-pathspecs", "restore", "--staged", "--"] + paths, cwd: brain.root, environment: env)
        } else {
            // Before the first commit there is nothing to restore from: the paths leave the index, the files stay.
            try shell.check("/usr/bin/git", ["--literal-pathspecs", "rm", "--cached", "-q", "-r", "--"] + paths, cwd: brain.root, environment: env)
        }
    }

    /// Adds everything and commits under the identity's name. Returns false if there was nothing to commit. Never used for
    /// a save: it would sign every account's pending notes and the person's own files (see `commit(paths:author:message:)`).
    @discardableResult
    public func commitAll(authorName: String, authorEmail: String, message: String) throws -> Bool {
        try requireGit()
        try shell.check("/usr/bin/git", ["add", "-A"], cwd: brain.root)
        guard try hasChanges() else { return false }
        try shell.check("/usr/bin/git", ["-c", "user.name=\(authorName)", "-c", "user.email=\(authorEmail)",
                                         "commit", "-q", "-m", message], cwd: brain.root)
        return true
    }

    /// The commit the memory is at, nil before the first save. Cheap: the graph asks it every few seconds and reads
    /// the history again only when it moved.
    public func head() -> String? {
        guard availability.isAvailable else { return nil }
        guard let result = try? shell.run("/usr/bin/git", ["rev-parse", "--verify", "-q", "HEAD"], cwd: brain.root), result.status == 0 else { return nil }
        let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    public func log(limit: Int = 50) throws -> [Entry] {
        try requireGit()
        guard try shell.run("/usr/bin/git", ["rev-parse", "--verify", "HEAD"], cwd: brain.root).status == 0 else { return [] }
        // core.quotePath=false: "décision.md" comes out as it is written, not as "d\303\251cision.md" in quotes.
        let out = try shell.check("/usr/bin/git", ["-c", "core.quotePath=false", "log", "-n", "\(limit)", "--name-only",
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
