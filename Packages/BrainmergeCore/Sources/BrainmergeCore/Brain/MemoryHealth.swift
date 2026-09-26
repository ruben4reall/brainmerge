import Foundation

/// A project's index, `memory/<project>/MEMORY.md`: the one file of a project's memory Claude Code reads at the start of
/// every session, and only its first lines. A note the index does not name is only found if a session happens to look.
public enum MemoryIndex {
    public static let fileName = "MEMORY.md"
    /// How many lines of a project's MEMORY.md Claude Code loads at the start of a session; the rest is read only when
    /// asked for. See Claude Code's memory docs: https://code.claude.com/docs/en/memory
    public static let loadedLines = 200

    /// A line of an index that links to notes.
    public struct Link: Equatable, Sendable {
        /// Counted from 1, like an editor does.
        public let line: Int
        /// The line as written, without its line break.
        public let text: String
        public let targets: [MemoryGraph.LinkTarget]
    }

    /// The lines as written, split on line breaks only: the last one is empty when the text ends with a line break.
    /// A carriage return stays at the end of its line.
    static func rawLines(_ text: String) -> [String] {
        text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
    }

    /// The lines as Claude Code counts them: a last line break ends a line, it does not start another.
    public static func lineCount(_ text: String) -> Int {
        guard let last = text.utf8.last else { return 0 }
        let breaks = text.utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
        return last == 10 ? breaks : breaks + 1
    }

    /// The lines that link to notes, both `[text](note.md)` and `[[note]]`, outside code blocks. Web links, images and
    /// other files are not notes.
    public static func links(in text: String) -> [Link] {
        var links: [Link] = []
        var fence: Unicode.Scalar?
        for (index, raw) in rawLines(text).enumerated() {
            var line = raw
            if line.unicodeScalars.last == "\r" { line = String(String.UnicodeScalarView(line.unicodeScalars.dropLast())) }
            if let marker = fenceMarker(line) {
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                continue
            }
            if fence != nil { continue }
            let targets = MemoryGraph.linkTargets(in: line).filter(isNote)
            if !targets.isEmpty { links.append(Link(line: index + 1, text: line, targets: targets)) }
        }
        return links
    }

    /// A line that opens or closes a code block: up to three spaces, then ``` or ~~~.
    static func fenceMarker(_ line: String) -> Unicode.Scalar? {
        let scalars = Array(line.unicodeScalars)
        var i = 0
        while i < scalars.count, i < 3, scalars[i] == " " { i += 1 }
        guard i + 2 < scalars.count, scalars[i] == "`" || scalars[i] == "~", scalars[i + 1] == scalars[i], scalars[i + 2] == scalars[i] else { return nil }
        return scalars[i]
    }

    static func isNote(_ target: MemoryGraph.LinkTarget) -> Bool {
        switch target {
        case .markdown(let path):
            return (path as NSString).pathExtension.lowercased() == "md"
        case .wiki(let name):
            let ext = (name as NSString).pathExtension.lowercased()
            return ext.isEmpty || ext == "md" || !(MemoryGraph.attachmentExtensions.contains(ext) || MemoryGraph.noteExtensions.contains(ext))
        }
    }
}

/// How an index's links find their notes, like the graph: a Markdown link from the index's folder (or from the memory's
/// top), a wiki link by path, then by the note's name anywhere, a note of the same folder first. Whatever the case.
struct NoteResolver {
    private var byPath: [String: String] = [:]
    private var byName: [String: [String]] = [:]

    init(notes: [String]) {
        for path in notes.sorted() {
            byPath[path.lowercased()] = path
            byName[MemoryGraphBuilder.noteName(path).lowercased(), default: []].append(path)
        }
    }

    /// The note a link of `memory/<folder>/MEMORY.md` leads to, nil when there is none.
    func resolve(_ target: MemoryGraph.LinkTarget, from folder: String) -> String? {
        let base = "memory/\(folder)"
        switch target {
        case .markdown(let relative):
            return MemoryGraphBuilder.collapse(base + "/" + relative).flatMap { byPath[$0.lowercased()] }
                ?? MemoryGraphBuilder.collapse(relative).flatMap { byPath[$0.lowercased()] }
        case .wiki(let name):
            for candidate in [base + "/" + name, base + "/" + name + ".md", name, name + ".md"] {
                if let hit = MemoryGraphBuilder.collapse(candidate).flatMap({ byPath[$0.lowercased()] }) { return hit }
            }
            let named = byName[MemoryGraphBuilder.noteName(name).lowercased()] ?? []
            return named.first { ($0 as NSString).deletingLastPathComponent == base } ?? named.first
        }
    }
}

/// The Tidy tab, and `brainmerge brain health`: which notes of a memory Claude Code will not load, and what else wants a
/// look. Read only: the words it shows and the buttons of MemoryTidy are the only way anything changes, on a click.
public enum MemoryHealth {
    /// A change older than this that no save committed is said.
    public static let unsavedAfter: TimeInterval = 86_400
    /// The folders of Claude's quick sessions (`scratch-2026-09-23-5050ce`): each is used once, and no later session reads it.
    public static let quickSessionPrefix = "scratch-"

    public static func isOneOff(_ folder: String) -> Bool { folder.hasPrefix(quickSessionPrefix) }

    /// What the analysis looks at, all read beforehand (see `read`), so the analysis itself touches nothing.
    public struct Input: Sendable {
        public var scan: MemoryScan
        /// Each project's MEMORY.md, by project folder.
        public var indexes: [String: String]
        /// The accounts that may have left a copy when their notes were linked (`deploy.<account>.md`).
        public var accountSlugs: Set<String>
        /// The paths no save committed yet, and when each last changed.
        public var pending: [String: Date]
        /// The notes the secret guard held back: their own banner says so.
        public var held: Set<String>
        /// The empty folders hidden from the tab.
        public var hidden: Set<String>
        public var now: Date
        public init(scan: MemoryScan, indexes: [String: String] = [:], accountSlugs: Set<String> = [], pending: [String: Date] = [:],
                    held: Set<String> = [], hidden: Set<String> = [], now: Date = Date()) {
            self.scan = scan; self.indexes = indexes; self.accountSlugs = accountSlugs; self.pending = pending
            self.held = held; self.hidden = hidden; self.now = now
        }
    }

    /// In the order the rows are shown within a group.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case noIndex, indexTooLong, notInIndex, oneOffNotes, emptyOneOffFolders, conflictCopy, danglingLines, unsaved
    }

    public enum GroupID: String, Codable, Sendable, CaseIterable {
        case notLoaded, oneOff, copies, dangling, unsaved

        public var title: String {
            switch self {
            case .notLoaded: "Notes Claude will not load"
            case .oneOff: "Notes in one-off folders"
            case .copies: "Copies left when linking"
            case .dangling: "Index lines that point nowhere"
            case .unsaved: "Changes not saved for more than a day"
            }
        }
    }

    /// One row of the tab. Paths are relative to the memory, never absolute.
    public struct Item: Encodable, Equatable, Sendable, Identifiable {
        public let kind: Kind
        /// The project folder it is about, when there is one.
        public let project: String?
        public let sentence: String
        /// The quiet second line: the notes' names, the folder, the two copies.
        public let detail: String?
        /// The notes, index or folders it is about, sorted (for a copy: the note, then its copy).
        public let files: [String]
        /// An index's number of lines, for one that is too long.
        public let lines: Int?
        /// For notes in a one-off folder: the projects their names mention, the likeliest first.
        public let suggested: [String]
        public var id: String { "\(kind.rawValue):\(project ?? ""):\(files.joined(separator: "|"))" }

        init(_ kind: Kind, project: String?, sentence: String, detail: String? = nil, files: [String], lines: Int? = nil, suggested: [String] = []) {
            self.kind = kind; self.project = project; self.sentence = sentence; self.detail = detail; self.files = files
            self.lines = lines; self.suggested = suggested
        }

        enum CodingKeys: String, CodingKey { case kind, project, sentence, detail, files, lines, suggested }
        /// Every key, every time (null when empty): scripts reading `brain health --json` can rely on its shape.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(project, forKey: .project)
            try container.encode(sentence, forKey: .sentence)
            try container.encode(detail, forKey: .detail)
            try container.encode(files, forKey: .files)
            try container.encode(lines, forKey: .lines)
            try container.encode(suggested, forKey: .suggested)
        }
    }

    public struct Group: Encodable, Equatable, Sendable, Identifiable {
        public let id: GroupID
        public let title: String
        public let items: [Item]
    }

    public struct Report: Encodable, Equatable, Sendable {
        /// The number of rows: the tab's "Tidy (4)".
        public var count: Int
        /// The groups with something to say, in the tab's order.
        public var groups: [Group]
        /// The project folders a note can be filed under (not the one-off ones), sorted.
        public var projects: [String]
        public init(count: Int = 0, groups: [Group] = [], projects: [String] = []) { self.count = count; self.groups = groups; self.projects = projects }
    }

    // MARK: Reading

    /// Reads what the analysis needs, and changes nothing: the walk the graph uses, each project's index (a megabyte at
    /// most), what git has not committed (asked without refreshing git's index, which a save may hold; nothing when git
    /// is missing), the accounts the memory knows and the hidden folders.
    public static func read(brain: Brain, git: BrainGit, accountSlugs: Set<String>, held: Set<String>, now: Date = Date()) -> Input {
        let scan = MemoryGraphBuilder(root: brain.root).memoryScan()
        let present = Set(scan.notes.map(\.path))
        var indexes: [String: String] = [:]
        for folder in scan.folders where present.contains("memory/\(folder)/\(MemoryIndex.fileName)") {
            indexes[folder] = readText(brain.memoryDir(forProject: folder).appending(path: MemoryIndex.fileName))
        }
        var pending: [String: Date] = [:]
        if FileManager.default.fileExists(atPath: brain.gitDir.path),
           let changed = try? git.status(scope: Brain.ownEditsScope, optionalLocks: false) {
            for path in changed { pending[path] = OwnEdits.newestChange(of: [path], in: brain) ?? now }
        }
        let known = (try? IdentityRegistry.load(brain.identitiesFile))?.identities.keys.map { $0 } ?? []
        return Input(scan: scan, indexes: indexes, accountSlugs: accountSlugs.union(known), pending: pending, held: held,
                     hidden: MemoryTidy.hidden(in: brain), now: now)
    }

    static func readText(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        return String(decoding: (try? handle.read(upToCount: 1 << 20)) ?? Data(), as: UTF8.self)
    }

    /// The notes of a project folder that its index could name: not the index itself, not what `_archive/` keeps.
    static func notes(of folder: String, in scan: MemoryScan) -> [String] {
        let prefix = "memory/\(folder)/"
        return scan.notes.map(\.path).filter { path in
            guard path.hasPrefix(prefix), path != prefix + MemoryIndex.fileName else { return false }
            return !path.dropFirst(prefix.count).hasPrefix(MemoryTidy.archiveFolder + "/")
        }.sorted()
    }

    // MARK: The analysis

    public static func analyze(_ input: Input) -> Report {
        let scan = input.scan
        guard !scan.refused else { return Report() }
        let projects = scan.folders.filter { !isOneOff($0) }.sorted()
        let resolver = NoteResolver(notes: scan.notes.map(\.path))
        var groups: [GroupID: [Item]] = [:]
        var emptyOneOff: [String] = []
        for folder in scan.folders.sorted() {
            let notes = notes(of: folder, in: scan)
            if isOneOff(folder) {
                // One group per folder: a quick session's folder is only said to be one.
                if !notes.isEmpty {
                    groups[.oneOff, default: []].append(Item(.oneOffNotes, project: folder, sentence: oneOffSentence(notes.count), detail: folder,
                                                             files: notes, suggested: suggestions(for: notes, among: projects)))
                } else if !input.hidden.contains(folder) {
                    emptyOneOff.append(folder)
                }
                continue
            }
            let copies = notes.compactMap { note in original(of: note, accounts: input.accountSlugs).flatMap { notes.contains($0) ? ($0, note) : nil } }
            for (note, copy) in copies {
                let name = (note as NSString).lastPathComponent
                groups[.copies, default: []].append(Item(.conflictCopy, project: folder, sentence: "\(folder) has two copies of \(name).",
                                                         detail: "\(name) and \((copy as NSString).lastPathComponent)", files: [note, copy]))
            }
            let copyPaths = Set(copies.map(\.1))
            let named = notes.filter { !copyPaths.contains($0) }
            let indexPath = "memory/\(folder)/\(MemoryIndex.fileName)"
            guard let index = input.indexes[folder] else {
                if !named.isEmpty {
                    let them = named.count == 1 ? "it" : "them"
                    groups[.notLoaded, default: []].append(Item(.noIndex, project: folder,
                                                                sentence: "\(folder) has \(count(named.count, "note")) and no index, so no session loads \(them).",
                                                                detail: list(named.map(fileName)), files: named))
                }
                continue
            }
            var early = Set<String>(), late = Set<String>(), nowhere: [String] = []
            for link in MemoryIndex.links(in: index) {
                for target in link.targets {
                    if let note = resolver.resolve(target, from: folder) {
                        if link.line <= MemoryIndex.loadedLines { early.insert(note) } else { late.insert(note) }
                    } else if case .markdown(let written) = target, !nowhere.contains(written) {
                        nowhere.append(written)
                    } else if case .wiki(let written) = target, !nowhere.contains(written) {
                        nowhere.append(written)
                    }
                }
            }
            let lines = MemoryIndex.lineCount(index)
            if lines > MemoryIndex.loadedLines {
                let cut = named.filter { late.contains($0) && !early.contains($0) }
                groups[.notLoaded, default: []].append(Item(.indexTooLong, project: folder,
                                                            sentence: "\(folder)'s index has \(lines) lines. Claude Code loads the first \(MemoryIndex.loadedLines).",
                                                            detail: cut.isEmpty ? nil : "Named after line \(MemoryIndex.loadedLines): " + list(cut.map(fileName)),
                                                            files: [indexPath], lines: lines))
            }
            let missing = named.filter { !early.contains($0) && !late.contains($0) }
            if !missing.isEmpty {
                let sentence = missing.count == 1 ? "1 note of \(folder) is missing from its index." : "\(missing.count) notes of \(folder) are missing from its index."
                groups[.notLoaded, default: []].append(Item(.notInIndex, project: folder, sentence: sentence, detail: list(missing.map(fileName)), files: missing))
            }
            if !nowhere.isEmpty {
                let sentence = nowhere.count == 1 ? "\(folder)'s index names 1 note that is not there." : "\(folder)'s index names \(nowhere.count) notes that are not there."
                groups[.dangling, default: []].append(Item(.danglingLines, project: folder, sentence: sentence, detail: list(nowhere), files: [indexPath]))
            }
        }
        if !emptyOneOff.isEmpty {
            let sentence = emptyOneOff.count == 1 ? "1 quick session folder is empty." : "\(emptyOneOff.count) quick session folders are empty."
            groups[.oneOff, default: []].append(Item(.emptyOneOffFolders, project: nil, sentence: sentence, detail: list(emptyOneOff),
                                                     files: emptyOneOff.map { "memory/\($0)" }))
        }
        let stale = input.pending.filter { input.now.timeIntervalSince($0.value) > unsavedAfter && !input.held.contains($0.key) }.keys.sorted()
        if !stale.isEmpty {
            let sentence = stale.count == 1 ? "1 change has not been saved for more than a day." : "\(stale.count) changes have not been saved for more than a day."
            groups[.unsaved] = [Item(.unsaved, project: nil, sentence: sentence, detail: list(stale.map(fileName)), files: stale)]
        }
        let order = Dictionary(uniqueKeysWithValues: Kind.allCases.enumerated().map { ($1, $0) })
        let shown = GroupID.allCases.compactMap { id -> Group? in
            guard let items = groups[id], !items.isEmpty else { return nil }
            // By project, then in the kinds' order; rows about no project (the empty folders) come last.
            let sorted = items.sorted { a, b in
                if a.project != b.project { return (a.project ?? "\u{10FFFF}") < (b.project ?? "\u{10FFFF}") }
                return order[a.kind]! < order[b.kind]!
            }
            return Group(id: id, title: id.title, items: sorted)
        }
        return Report(count: shown.reduce(0) { $0 + $1.items.count }, groups: shown, projects: projects)
    }

    /// The note an account's copy stands beside: `deploy.work.md` for `deploy.md`, when `work` is an account (see
    /// MemoryWiring.adopt, which names a copy that way).
    static func original(of path: String, accounts: Set<String>) -> String? {
        let name = (path as NSString).lastPathComponent
        guard name.lowercased().hasSuffix(".md") else { return nil }
        let stem = String(name.dropLast(3))
        guard let dot = stem.lastIndex(of: "."), dot != stem.startIndex else { return nil }
        let slug = String(stem[stem.index(after: dot)...])
        guard accounts.contains(slug) else { return nil }
        return (path as NSString).deletingLastPathComponent + "/" + stem[..<dot] + ".md"
    }

    /// The projects a note's name mentions (`beehive-pricing.md` and `project_beehive.md` go to beehive), by whole words in
    /// order: the one most notes mention first, then the more specific name, then by name.
    public static func suggestions(for notes: [String], among projects: [String]) -> [String] {
        let names = notes.map { words(MemoryGraphBuilder.noteName($0)) }
        let scored = projects.compactMap { project -> (String, Int)? in
            let wanted = words(project)
            guard !wanted.isEmpty else { return nil }
            let hits = names.filter { contains($0, wanted) }.count
            return hits > 0 ? (project, hits) : nil
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.count != b.0.count { return a.0.count > b.0.count }
            return a.0 < b.0
        }.map(\.0)
    }

    static func words(_ text: String) -> [String] { text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }

    static func contains(_ words: [String], _ run: [String]) -> Bool {
        guard run.count <= words.count else { return false }
        return (0...(words.count - run.count)).contains { Array(words[$0..<($0 + run.count)]) == run }
    }

    static func oneOffSentence(_ n: Int) -> String {
        n == 1 ? "1 note sits in a quick session's folder that no later session reads."
            : "\(n) notes sit in a quick session's folder that no later session reads."
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    static func fileName(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// "a.md, b.md, c.md and 2 more": a second line stays one line.
    static func list(_ names: [String]) -> String {
        names.count <= 3 ? names.joined(separator: ", ") : names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more"
    }
}
