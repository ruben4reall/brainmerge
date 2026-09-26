import Foundation

/// What one account wrote in a memory since its last save, one path per line in `.brainmerge/touched/<slug>` (ignored by
/// git). The PostToolUse hook appends to it; the account's save takes it, commits those paths only, and puts back what it
/// could not save. Other accounts' notes and the person's own files are never in it, so they are never signed by this account.
///
/// Several hooks and a save can meet on the same list: every append and every read holds a lock on the file, and a writer
/// that finds the list moved away meanwhile (a save took it) writes to the new one, so no line is ever lost.
public struct TouchedLedger: Sendable {
    public let brain: Brain
    public let slug: String
    public init(brain: Brain, slug: String) { self.brain = brain; self.slug = slug }

    public var file: URL { brain.touchedDir.appending(path: slug) }
    /// The list a save is working on: kept aside until it is done, taken again by the next save if it never finished.
    public var sending: URL { brain.touchedDir.appending(path: "\(slug).sending") }

    /// Adds a path, relative to the memory (`memory/acme/deploy.md`). A name that would break the one-per-line list is skipped.
    public func append(_ path: String) throws {
        guard !path.isEmpty, !path.contains(where: \.isNewline) else { return }
        try FileManager.default.createDirectory(at: brain.touchedDir, withIntermediateDirectories: true)
        try Self.appendLines([path], to: file)
    }

    /// Moves the list aside and returns its paths, each once, in the order they were written. A list left aside by a save
    /// that never finished comes first.
    public func take() throws -> [String] {
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            if fm.fileExists(atPath: sending.path) {
                try Self.drain(file, into: sending)
            } else if rename(file.path, sending.path) != 0, errno != ENOENT {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        guard fm.fileExists(atPath: sending.path) else { return [] }
        return Self.unique(try Self.readLocked(sending))
    }

    /// Ends a save: the paths it did not save go back on the list for the next one, and the list it took is removed.
    public func finish(keeping unsaved: [String]) throws {
        if !unsaved.isEmpty {
            try FileManager.default.createDirectory(at: brain.touchedDir, withIntermediateDirectories: true)
            try Self.appendLines(unsaved, to: file)
        }
        try? FileManager.default.removeItem(at: sending)
    }

    /// The memory a written file belongs to, and its path there (`memory/acme/deploy.md`). Claude Code names the file through
    /// the account's link (`projects/<slug>/memory/deploy.md`), so its folder is resolved first; only a file inside a
    /// memory's `memory/` folder counts.
    public static func locate(_ filePath: String, in brains: [Brain]) -> (brain: Brain, path: String)? {
        guard filePath.hasPrefix("/"), !filePath.contains(where: \.isNewline) else { return nil }
        let written = URL(fileURLWithPath: filePath).standardizedFileURL
        let name = written.lastPathComponent
        let folder = written.deletingLastPathComponent().resolvingSymlinksInPath().path
        for brain in brains {
            let notes = brain.memoryDir.standardizedFileURL.resolvingSymlinksInPath().path
            guard folder == notes || folder.hasPrefix(notes + "/") else { continue }
            let inside = String(folder.dropFirst(notes.count)).split(separator: "/").map(String.init) + [name]
            return (brain, (["memory"] + inside).joined(separator: "/"))
        }
        return nil
    }

    /// Every path some account wrote and has not saved yet: the person's own edits never include them.
    public static func claimed(in brain: Brain) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: brain.touchedDir.path)) ?? []
        return Set(names.flatMap { name in
            (try? readLocked(brain.touchedDir.appending(path: name))) ?? []
        })
    }

    // MARK: Locked file access

    /// Appends under an exclusive lock. When the path no longer names the file that was opened (a save moved it away
    /// between the open and the lock), the lines go to the file now at that path instead.
    static func appendLines(_ lines: [String], to url: URL) throws {
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        for _ in 0..<50 {
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
            guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { close(fd) }
            guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { flock(fd, LOCK_UN) }
            var opened = stat(), current = stat()
            guard fstat(fd, &opened) == 0 else { throw CocoaError(.fileWriteUnknown) }
            guard stat(url.path, &current) == 0, current.st_ino == opened.st_ino, current.st_dev == opened.st_dev else { continue }
            let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard written == data.count else { throw CocoaError(.fileWriteUnknown) }
            return
        }
        throw CocoaError(.fileWriteUnknown)
    }

    /// Reads under the lock: a writer that got the file before it moved finishes first.
    static func readLocked(_ url: URL) throws -> [String] {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        flock(fd, LOCK_SH)
        defer { flock(fd, LOCK_UN) }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    /// Moves the lines of `source` to the end of `target` and removes `source`, holding `source`'s lock throughout: a
    /// writer waiting on it then finds it gone and writes a new list.
    static func drain(_ source: URL, into target: URL) throws {
        let fd = open(source.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        if !lines.isEmpty { try appendLines(lines, to: target) }
        unlink(source.path)
    }

    static func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }
}
