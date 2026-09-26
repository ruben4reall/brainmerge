import Foundation

/// The Tidy tab's buttons: one click, one commit, as You (the person clicked), under the memory's lock. File under moves a
/// quick session's notes into a project with their index lines, Keep this one puts the other copy of a note in the
/// project's `_archive/`, Hide notes empty folders in `.brainmerge/hidden.json`. Nothing moves without a click, a note
/// written in the last two minutes or with changes no save committed yet is never moved, and no folder is ever deleted:
/// accounts link to them.
///
/// Only notes whose content is already committed move, so a move commits no new line: the secret guard read every one of
/// them when they were saved, and no account's words are signed as yours.
public struct MemoryTidy: Sendable {
    /// A note changed more recently than this may still be being written.
    public static let settling: TimeInterval = 120
    /// Where Keep this one puts the other copy, inside the project's folder: never loaded, never deleted.
    public static let archiveFolder = "_archive"

    public let brain: Brain
    public let git: BrainGit
    public let lockTimeout: TimeInterval
    public init(brain: Brain, git: BrainGit, lockTimeout: TimeInterval = 5) { self.brain = brain; self.git = git; self.lockTimeout = lockTimeout }

    // MARK: File under

    /// What File under would do, for its preview: read only.
    public struct Plan: Equatable, Sendable {
        public let from: String
        public let to: String
        /// The notes that move, relative to the memory, sorted.
        public let notes: [String]
        /// How many lines of the folder's index go with them.
        public let indexLines: Int

        /// "Move 2 notes from scratch-2026-09-23-5050ce to brainmerge, with their index lines."
        public var preview: String {
            let what = notes.count == 1 ? "1 note" : "\(notes.count) notes"
            let lines = indexLines == 0 ? "" : notes.count == 1 ? ", with its index line" : ", with their index lines"
            return "Move \(what) from \(from) to \(to)\(lines)."
        }
    }

    public func plan(filing folder: String, under project: String) throws -> Plan {
        try Self.checkName(folder); try Self.checkName(project)
        let (notes, lines, _) = layout(folder)
        return Plan(from: folder, to: project, notes: notes, indexLines: lines.count)
    }

    /// Moves the plan's notes with `git mv` and their index lines as they are written, and commits it all at once: "You filed
    /// 2 notes under brainmerge". Refused, with nothing changed, when the folder no longer matches the preview, a note or
    /// an index is being written or not saved, a note of that name is already there, or your own git is stopped half way.
    /// Returns the paths committed.
    @discardableResult
    public func file(_ plan: Plan, now: Date = Date()) throws -> [String] {
        try Self.checkName(plan.from); try Self.checkName(plan.to)
        return try git.withLock(timeout: lockTimeout) {
            guard !(try git.operationUnfinished()) else { throw BrainmergeError.gitOperationUnfinished }
            let (notes, lines, source) = layout(plan.from)
            // Something changed since the preview: a session is at work there.
            guard Plan(from: plan.from, to: plan.to, notes: notes, indexLines: lines.count) == plan else { throw BrainmergeError.noteBeingWritten }
            guard !notes.isEmpty else { return [] }
            let sourceIndex = "memory/\(plan.from)/\(MemoryIndex.fileName)", targetIndex = "memory/\(plan.to)/\(MemoryIndex.fileName)"
            let moves = notes.map { ($0, "memory/\(plan.to)/" + $0.dropFirst("memory/\(plan.from)/".count)) }
            for (_, destination) in moves where exists(destination) {
                throw BrainmergeError.noteExists(name: (destination as NSString).lastPathComponent, project: plan.to)
            }
            let indexes = lines.isEmpty ? [] : [sourceIndex] + (exists(targetIndex) ? [targetIndex] : [])
            try refuseUnsettled(notes + indexes, now: now)

            let sourceData = contents(sourceIndex), targetData = contents(targetIndex)
            var done: [(String, String)] = []
            do {
                for (from, to) in moves { try git.move(from, to: to); done.append((from, to)) }
                if !lines.isEmpty {
                    let (kept, moved) = Self.split(source ?? "", taking: Set(lines))
                    try write(kept, to: sourceIndex)
                    try write(Self.appending(moved, to: targetData.map { String(decoding: $0, as: UTF8.self) } ?? ""), to: targetIndex)
                }
                let paths = moves.flatMap { [$0.0, $0.1] } + (lines.isEmpty ? [] : [sourceIndex, targetIndex])
                return try git.commit(paths: paths, author: OwnEdits.author) { _ in
                    "\(OwnEdits.author.name) \(MemorySentence.filed(notes.count, under: plan.to))"
                }
            } catch {
                // Everything back where it was: the notes (git's index with them) and both indexes as they were.
                for (from, to) in done.reversed() { try? git.move(to, to: from) }
                if !lines.isEmpty {
                    restore(sourceIndex, sourceData)
                    restore(targetIndex, targetData)
                }
                throw error
            }
        }
    }

    // MARK: Keep this one

    /// Keeps `kept` and moves `other` to `memory/<project>/_archive/` (a number added when that name is taken there), in
    /// one commit: "You kept one copy of deploy.md". An account's copy kept (`deploy.work.md` over `deploy.md`) takes the
    /// note's name, so the index still finds it. Returns the paths committed.
    @discardableResult
    public func keep(_ kept: String, over other: String, now: Date = Date()) throws -> [String] {
        try git.withLock(timeout: lockTimeout) {
            guard !(try git.operationUnfinished()) else { throw BrainmergeError.gitOperationUnfinished }
            let parts = other.split(separator: "/").map(String.init)
            guard parts.count >= 3, parts[0] == "memory", kept.hasPrefix("memory/\(parts[1])/") else { throw BrainmergeError.nameInvalid }
            try refuseUnsettled([kept, other], now: now)
            let otherName = (other as NSString).lastPathComponent
            let takesName = (other as NSString).deletingLastPathComponent == (kept as NSString).deletingLastPathComponent
                && otherName.lowercased().hasSuffix(".md") && (kept as NSString).lastPathComponent.hasPrefix(String(otherName.dropLast(3)) + ".")
            let archived = archivePath(project: parts[1], name: otherName)
            let name = takesName ? otherName : (kept as NSString).lastPathComponent
            var done: [(String, String)] = []
            do {
                try git.move(other, to: archived); done.append((other, archived))
                if takesName { try git.move(kept, to: other); done.append((kept, other)) }
                let paths = [other, archived] + (takesName ? [kept] : [])
                return try git.commit(paths: paths, author: OwnEdits.author) { _ in "\(OwnEdits.author.name) \(MemorySentence.kept(name))" }
            } catch {
                for (from, to) in done.reversed() { try? git.move(to, to: from) }
                throw error
            }
        }
    }

    // MARK: Hide

    struct HiddenFile: Codable { var folders: [String] }

    /// The empty folders hidden from the Tidy tab, by name.
    public static func hidden(in brain: Brain) -> Set<String> {
        guard let data = try? Data(contentsOf: brain.hiddenFile), let file = try? JSONDecoder().decode(HiddenFile.self, from: data) else { return [] }
        return Set(file.folders)
    }

    /// Adds folders to the hidden list and commits it: "You hid 3 empty folders from Tidy". The folders stay where they
    /// are. Nothing new to hide: no commit. Returns the paths committed.
    @discardableResult
    public func hide(_ folders: [String]) throws -> [String] {
        for folder in folders { try Self.checkName(folder) }
        return try git.withLock(timeout: lockTimeout) {
            guard !(try git.operationUnfinished()) else { throw BrainmergeError.gitOperationUnfinished }
            var hidden = Self.hidden(in: brain)
            let new = Set(folders).subtracting(hidden)
            guard !new.isEmpty else { return [] }
            hidden.formUnion(new)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
            try encoder.encode(HiddenFile(folders: hidden.sorted())).write(to: brain.hiddenFile, options: .atomic)
            return try git.commit(paths: [".brainmerge/hidden.json"], author: OwnEdits.author) { _ in
                "\(OwnEdits.author.name) \(MemorySentence.hid(new.count))"
            }
        }
    }

    // MARK: Helpers

    /// A folder is named, never a path: no way out of `memory/`.
    static func checkName(_ name: String) throws {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !name.hasPrefix(".") else { throw BrainmergeError.nameInvalid }
    }

    /// The notes of a folder, the line numbers of its index that name them, and that index's text.
    func layout(_ folder: String) -> (notes: [String], lines: [Int], index: String?) {
        let scan = MemoryGraphBuilder(root: brain.root).memoryScan()
        let notes = MemoryHealth.notes(of: folder, in: scan)
        let moving = Set(notes)
        guard let data = contents("memory/\(folder)/\(MemoryIndex.fileName)") else { return (notes, [], nil) }
        let text = String(decoding: data, as: UTF8.self)
        let resolver = NoteResolver(notes: scan.notes.map(\.path))
        let lines = MemoryIndex.links(in: text).filter { link in
            link.targets.contains { resolver.resolve($0, from: folder).map(moving.contains) == true }
        }.map(\.line)
        return (notes, lines, text)
    }

    /// The text without the lines at these numbers (from 1), and those lines as they were written.
    static func split(_ text: String, taking numbers: Set<Int>) -> (kept: String, taken: [String]) {
        let lines = MemoryIndex.rawLines(text)
        var kept: [String] = [], taken: [String] = []
        for (index, line) in lines.enumerated() {
            if numbers.contains(index + 1) { taken.append(line) } else { kept.append(line) }
        }
        return (kept.joined(separator: "\n"), taken)
    }

    /// The lines added at the end of an index, on lines of their own.
    static func appending(_ lines: [String], to text: String) -> String {
        guard !lines.isEmpty else { return text }
        let lead = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        return text + lead + lines.map { $0 + "\n" }.joined()
    }

    /// Refused while a note may still be written (changed in the last two minutes, or dated ahead), or has changes no save
    /// committed yet.
    func refuseUnsettled(_ paths: [String], now: Date) throws {
        for path in paths {
            let date = (try? FileManager.default.attributesOfItem(atPath: brain.root.appending(path: path).path))?[.modificationDate] as? Date
            if let date, now.timeIntervalSince(date) < Self.settling { throw BrainmergeError.noteBeingWritten }
        }
        guard (try git.status(scope: paths)).isEmpty else { throw BrainmergeError.noteNotSaved }
    }

    /// `memory/<project>/_archive/<name>`, or `<name>-2.md` and on when that is taken.
    func archivePath(project: String, name: String) -> String {
        let folder = "memory/\(project)/\(Self.archiveFolder)"
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = "\(folder)/\(name)"
        var number = 2
        while exists(candidate) {
            candidate = "\(folder)/\(stem)-\(number)" + (ext.isEmpty ? "" : ".\(ext)")
            number += 1
        }
        return candidate
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: brain.root.appending(path: path).path) }

    func contents(_ path: String) -> Data? { try? Data(contentsOf: brain.root.appending(path: path)) }

    func write(_ text: String, to path: String) throws {
        let url = brain.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Puts a file back as it was, or removes one that was not there.
    func restore(_ path: String, _ data: Data?) {
        let url = brain.root.appending(path: path)
        if let data { try? data.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
    }
}
