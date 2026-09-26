import Foundation

/// A memory folder seen as a graph, like Obsidian's graph view: every Markdown note is a node, every link between
/// two notes is an edge, and each project folder of Claude Code's memory (`memory/<project>/`) is a hub linked to
/// its notes. An Obsidian vault is drawn as Obsidian draws it instead: every file is its own node, no hubs.
/// Only file names and note text are read; nothing is written.
public struct MemoryGraph: Equatable, Sendable {
    /// How a folder is turned into a graph: a Brainmerge memory, with its project hubs, or an Obsidian vault, file by file.
    public enum Style: String, Sendable { case memory, vault }

    public struct Node: Equatable, Sendable, Identifiable {
        /// Notes (with a vault's canvases and bases), project hubs of a memory, and in a vault the attachments and
        /// the links that lead to no file, which the vault's settings show or hide.
        public enum Kind: String, Sendable { case note, project, attachment, unresolved }
        /// The note's path relative to the memory folder, "project:<name>" for a hub, "unresolved:<name>" for a link to nothing.
        public let id: String
        public let title: String
        public let kind: Kind
        /// The project folder under `memory/` it belongs to, when it does.
        public let project: String?
        public let modified: Date?
        /// The file behind the bubble, relative to the memory folder: the note itself, or a project's index
        /// (`memory/<project>/MEMORY.md`), nil for a project without an index.
        public let file: String?
        public init(id: String, title: String, kind: Kind, project: String?, modified: Date?, file: String? = nil) {
            self.id = id; self.title = title; self.kind = kind; self.project = project; self.modified = modified; self.file = file
        }
    }

    /// An undirected link: the two ends are stored in order, so A to B and B to A are one edge.
    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
        public init(_ a: String, _ b: String) { if a <= b { from = a; to = b } else { from = b; to = a } }
    }

    /// A link as written, from the note that holds it: A to B and B to A are two links, drawn as one edge.
    public struct Link: Hashable, Sendable {
        public let source: String
        public let target: String
        public init(source: String, target: String) { self.source = source; self.target = target }
    }

    public enum LinkTarget: Equatable, Sendable {
        case wiki(String)
        case markdown(String)
    }

    public var nodes: [Node]
    public var edges: [Edge]
    /// The links between notes with their direction (project hubs have none). Obsidian weighs its nodes by them.
    public var links: [Link]
    public init(nodes: [Node] = [], edges: [Edge] = [], links: [Link] = []) { self.nodes = nodes; self.edges = edges; self.links = links }

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
    public func degree(_ id: String) -> Int { edges.reduce(0) { $0 + ($1.from == id || $1.to == id ? 1 : 0) } }

    /// Obsidian's weight of each node: the links it holds plus the links that point at it. Nodes without links are left out.
    public func weights() -> [String: Int] {
        var weights: [String: Int] = [:]
        for link in links { weights[link.source, default: 0] += 1; weights[link.target, default: 0] += 1 }
        return weights
    }

    /// The project whose index a file is (`memory/<project>/MEMORY.md`), if it is one.
    static func indexedProject(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "memory" && parts[2] == "MEMORY.md" && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    /// The bubble a file is drawn as: a project's index is its project's bubble, any other note is its own.
    public static func nodeID(forFile path: String) -> String {
        indexedProject(path).map { "project:\($0)" } ?? path
    }

    /// Files of a vault that are not notes: images, documents, sounds, videos. Obsidian calls them attachments.
    static let attachmentExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "bmp", "tif", "tiff", "avif",
                                                    "pdf", "mp3", "m4a", "wav", "ogg", "flac", "mp4", "mov", "webm", "mkv",
                                                    "excalidraw", "zip", "csv", "json"]
    /// Files Obsidian always draws as nodes, whatever its attachment setting: notes, canvases and bases.
    static let noteExtensions: Set<String> = ["md", "canvas", "base"]

    /// The link targets written in a note: `[[target]]`, `[[target|alias]]`, `[[target#heading]]`, embeds, and Markdown
    /// links to local files, `[text](path.md)`, `[text](<path with spaces.md>)`, `[text](path.md "title")`. Web and mail
    /// links, inline code and fenced code blocks are ignored. A target that is no note of a memory (an image, a canvas)
    /// simply resolves to nothing there. One pass, linear in the length of the text.
    public static func linkTargets(in text: String) -> [LinkTarget] {
        var targets: [LinkTarget] = []
        let s = Array(text.unicodeScalars)
        let n = s.count
        var i = 0
        var lineStart = true
        var fence: Unicode.Scalar?
        func string(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(s[range])) }
        func endOfLine(_ from: Int) -> Int { var j = from; while j < n, s[j] != "\n" { j += 1 }; return j }
        while i < n {
            let c = s[i]
            if c == "\n" { lineStart = true; i += 1; continue }
            if lineStart {
                lineStart = false
                // A fence opens or closes on a line that starts (after up to three spaces) with ``` or ~~~.
                var j = i, spaces = 0
                while j < n, s[j] == " ", spaces < 3 { j += 1; spaces += 1 }
                if j + 2 < n, s[j] == "`" || s[j] == "~", s[j + 1] == s[j], s[j + 2] == s[j] {
                    if fence == nil { fence = s[j] } else if fence == s[j] { fence = nil }
                    i = endOfLine(j); continue
                }
            }
            if fence != nil { i = endOfLine(i); continue }
            switch c {
            case "`":
                // An inline code span ends at the next run of as many backticks on the same line.
                var run = 0, j = i
                while j < n, s[j] == "`" { run += 1; j += 1 }
                var k = j, closed: Int?
                while k < n, s[k] != "\n" {
                    if s[k] == "`" {
                        var m = 0, l = k
                        while l < n, s[l] == "`" { m += 1; l += 1 }
                        if m == run { closed = l; break }
                        k = l
                    } else { k += 1 }
                }
                i = closed ?? j
            case "[" where i + 1 < n && s[i + 1] == "[":
                var j = i + 2
                while j + 1 < n, s[j] != "\n", !(s[j] == "]" && s[j + 1] == "]") { j += 1 }
                guard j + 1 < n, s[j] == "]", s[j + 1] == "]" else { i = max(j, i + 2); continue }   // unclosed: move on, never rescan
                var target = string((i + 2)..<j)
                if let bar = target.firstIndex(of: "|") {
                    target = String(target[..<bar])
                    if target.hasSuffix("\\") { target.removeLast() }   // [[a\|b]] inside a table
                }
                if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
                target = target.trimmingCharacters(in: .whitespaces)
                if !target.isEmpty { targets.append(.wiki(target)) }
                i = j + 2
            case "]" where i + 1 < n && s[i + 1] == "(":
                var j = i + 2
                var destination: String?
                if j < n, s[j] == "<" {
                    var k = j + 1
                    while k < n, s[k] != ">", s[k] != "\n" { k += 1 }
                    if k < n, s[k] == ">" { destination = string((j + 1)..<k); j = k + 1 }
                } else {
                    var k = j
                    while k < n, s[k] != ")", s[k] != "\n", s[k] != " ", s[k] != "\t" { k += 1 }
                    destination = string(j..<k); j = k
                }
                // An optional title, then the closing parenthesis on the same line.
                while j < n, s[j] != ")", s[j] != "\n" { j += 1 }
                if var target = destination, j < n, s[j] == ")" {
                    if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
                    let lower = target.lowercased()
                    let ext = (lower as NSString).pathExtension
                    if !target.isEmpty, !lower.contains(":"), noteExtensions.contains(ext) || attachmentExtensions.contains(ext) {
                        targets.append(.markdown(target.removingPercentEncoding ?? target))
                    }
                    i = j + 1
                } else {
                    i += 2
                }
            default:
                i += 1
            }
        }
        return targets
    }
}

/// What one walk of a memory finds: its Markdown notes with their date and size, and the project folders under `memory/`,
/// the empty ones included (they are link targets). The graph and the Tidy tab (MemoryHealth) share this walk.
public struct MemoryScan: Equatable, Sendable {
    public struct Note: Equatable, Sendable {
        /// Relative to the memory folder: `memory/acme/deploy.md`.
        public let path: String
        public let modified: Date
        public let size: Int
        public init(path: String, modified: Date, size: Int) { self.path = path; self.modified = modified; self.size = size }
    }
    public var notes: [Note]
    /// The names of the folders directly under `memory/`, sorted.
    public var folders: [String]
    /// The folder itself could not be opened (see MemoryGraphBuilder.Result.refused).
    public var refused: Bool
    public init(notes: [Note] = [], folders: [String] = [], refused: Bool = false) { self.notes = notes; self.folders = folders; self.refused = refused }
}

/// Builds the graph of a memory folder and keeps what it read, so later builds only read the notes that changed.
/// Not thread-safe: use one builder from one place (the app drives it from a single background task).
public final class MemoryGraphBuilder: @unchecked Sendable {
    public struct Result: Equatable, Sendable {
        public var graph: MemoryGraph
        /// Notes added or modified since the previous build (all of them on the first build).
        public var changed: [String]
        public var removed: [String]
        /// How many notes were read on this build (observability: zero when nothing changed).
        public var readFiles: Int
        /// The folder holds more notes than `maxNotes`; the most recently modified ones were kept.
        public var truncated: Bool
        /// Same for a vault's attachments, capped apart: it only matters while the vault shows them.
        public var attachmentsTruncated = false
        /// The folder itself could not be opened: macOS or its permissions refused. Not the same as an empty folder.
        public var refused = false
    }

    /// Markdown notes are read for their links; a vault's canvases, bases and attachments are nodes known by name only.
    enum FileKind: Equatable { case markdown, unread, attachment }
    struct Entry { var modified: Date; var size: Int; var kind: FileKind; var targets: [MemoryGraph.LinkTarget] }

    /// The folder as given; `root` is where it really is, looked at by the first build.
    private let given: URL
    /// A memory kept in Dropbox or iCloud is often reached through a symlink: the folder it points to is read, by its
    /// real path, which is also how the walk spells the files it finds ("/private/var", not "/var"). Resolved by the
    /// first build, never when the builder is made: the app makes it on the main thread and builds off it, and the first
    /// look at a vault in Documents can make macOS ask, and wait for the answer.
    public private(set) lazy var root: URL = Self.realPath(given)
    public let style: MemoryGraph.Style
    public let maxNotes: Int
    /// Bytes read per note at most: links sit in the text, and a huge note must not stall the build.
    public let maxBytes: Int
    private var cache: [String: Entry] = [:]
    /// Every file of the last scan, drawn or not (hidden by the vault, or left out by the cap), by kind: a link to one
    /// of them finds its file, so it is never taken for a link to nothing.
    private var known: [String: FileKind] = [:]
    /// The date and size of every file of the last scan: a file drawn again (the vault shows it again, or the cap lets it
    /// in) that has not moved on disk is read but not reported as changed.
    private var stamps: [String: Stamp] = [:]
    private struct Stamp: Equatable { let modified: Date; let size: Int }
    private var built = false

    public init(root: URL, style: MemoryGraph.Style = .memory, maxNotes: Int = 2000, maxBytes: Int = 256 * 1024) {
        self.given = root; self.style = style; self.maxNotes = maxNotes; self.maxBytes = maxBytes
    }

    static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.standardizedFileURL.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    static let skippedFolders: Set<String> = [".git", ".obsidian", ".brainmerge", ".trash", ".Trash", "node_modules", ".smart-connections"]

    /// The files of the graph under the folder, as relative paths with their date, size and kind: Markdown notes, and in
    /// a vault its canvases, bases and attachments. Hidden folders are skipped, and so are symlinks: a note always is a
    /// file of this folder, never something a link points to elsewhere.
    /// One `fts` walk that gets each file's date and size with its name: fifty thousand files take a fraction of a second.
    /// The folders directly under `memory/` come with it, empty or not.
    func scan() -> (files: [(path: String, modified: Date, size: Int, kind: FileKind)], folders: [String], refused: Bool) {
        var files: [(String, Date, Int, FileKind)] = []
        var folders: [String] = []
        var refused = false
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let start = strdup(root.path) else { return ([], [], false) }
        defer { free(start) }
        var roots: [UnsafeMutablePointer<CChar>?] = [start, nil]
        // FTS_PHYSICAL: symlinks are reported as links and never followed.
        guard let fts = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return ([], [], false) }
        defer { fts_close(fts) }
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            // The folder itself refused (EPERM from macOS's privacy guard, EACCES from its permissions): said apart
            // from an empty folder. A locked folder inside is only skipped.
            if entry.pointee.fts_level == 0, info == FTS_NS || info == FTS_DNR || info == FTS_ERR,
               entry.pointee.fts_errno == EPERM || entry.pointee.fts_errno == EACCES {
                refused = true
            }
            guard let cPath = entry.pointee.fts_path else { continue }
            let path = String(cString: cPath)
            let name = (path as NSString).lastPathComponent
            if info == FTS_D {
                if entry.pointee.fts_level > 0, Self.skippedFolders.contains(name) || name.hasPrefix(".") { fts_set(fts, entry, FTS_SKIP); continue }
                if entry.pointee.fts_level == 2, path.hasPrefix(base + "memory/") { folders.append(name) }
                continue
            }
            guard info == FTS_F, !name.hasPrefix("."), path.hasPrefix(base), let kind = kind(of: name),
                  let stat = entry.pointee.fts_statp?.pointee else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec) + TimeInterval(stat.st_mtimespec.tv_nsec) / 1e9)
            files.append((String(path.dropFirst(base.count)), modified, Int(stat.st_size), kind))
        }
        return (files, folders, refused)
    }

    /// The notes and project folders of a memory, from the same walk as the graph, read now (see MemoryHealth).
    public func memoryScan() -> MemoryScan {
        let (files, folders, refused) = scan()
        let notes = files.filter { $0.kind == .markdown }.map { MemoryScan.Note(path: $0.path, modified: $0.modified, size: $0.size) }
        return MemoryScan(notes: notes.sorted { $0.path < $1.path }, folders: folders.sorted(), refused: refused)
    }

    func kind(of name: String) -> FileKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "md" { return .markdown }
        guard style == .vault else { return nil }
        if MemoryGraph.noteExtensions.contains(ext) { return .unread }
        return MemoryGraph.attachmentExtensions.contains(ext) ? .attachment : nil
    }

    /// The bubble a file is drawn as: in a memory a project's index is its project's bubble, in a vault every file is its own.
    func nodeID(forFile path: String) -> String { style == .memory ? MemoryGraph.nodeID(forFile: path) : path }

    /// `showing`: whether the vault shows a file, by its path (see ObsidianGraphFilter.showsFile). The files it hides
    /// are neither read nor counted against the cap; a memory shows every note.
    public func build(showing shows: (_ path: String, _ attachment: Bool) -> Bool = { _, _ in true }) -> Result {
        let (files, _, refused) = scan()
        known = Dictionary(files.map { ($0.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let before = stamps
        stamps = Dictionary(files.map { ($0.path, Stamp(modified: $0.modified, size: $0.size)) }, uniquingKeysWith: { first, _ in first })
        // Notes and attachments are capped apart, so a vault full of images never pushes its notes out.
        func capped(_ list: [(path: String, modified: Date, size: Int, kind: FileKind)]) -> [(path: String, modified: Date, size: Int, kind: FileKind)] {
            list.count > maxNotes ? Array(list.sorted { $0.modified > $1.modified }.prefix(maxNotes)) : list
        }
        let shown = files.filter { shows($0.path, $0.kind == .attachment) }
        let notes = shown.filter { $0.kind != .attachment }, attachments = shown.filter { $0.kind == .attachment }
        var changed: [String] = []
        var read = 0
        var next: [String: Entry] = [:]
        for file in capped(notes) + capped(attachments) {
            if let entry = cache[file.path], entry.modified == file.modified, entry.size == file.size, entry.kind == file.kind {
                next[file.path] = entry
                continue
            }
            var targets: [MemoryGraph.LinkTarget] = []
            if file.kind == .markdown {
                targets = MemoryGraph.linkTargets(in: readText(root.appending(path: file.path)))
                read += 1
            }
            next[file.path] = Entry(modified: file.modified, size: file.size, kind: file.kind, targets: targets)
            if !built || before[file.path] != Stamp(modified: file.modified, size: file.size) { changed.append(file.path) }
        }
        let removed = cache.keys.filter { next[$0] == nil }
        cache = next
        built = true
        // Reported by bubble: a project's index that changed is its project's bubble that changed.
        let ids = { (paths: [String]) in Array(Set(paths.map(self.nodeID(forFile:)))).sorted() }
        return Result(graph: makeGraph(), changed: ids(changed), removed: ids(removed), readFiles: read,
                      truncated: notes.count > maxNotes, attachmentsTruncated: attachments.count > maxNotes, refused: refused)
    }

    private func readText(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func project(of path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count >= 3 && parts[0] == "memory" ? String(parts[1]) : nil
    }

    /// A path with its `.` and `..` resolved; nil when it climbs above the memory folder.
    static func collapse(_ path: String) -> String? {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast(); continue }
            parts.append(part)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// A note's name as Obsidian shows it: the file name without its `.md`, and nothing else removed ("Node.js").
    /// Any other file keeps its extension ("Board.canvas").
    static func noteName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private func makeGraph() -> MemoryGraph {
        let paths = cache.keys.sorted()
        let vault = style == .vault
        // Links resolve like Obsidian: an exact path first, then the note name anywhere, whatever the case,
        // preferring a note in the same folder. A link without an extension means a Markdown note.
        var byPath: [String: String] = [:]
        var byName: [String: [String]] = [:]
        for path in known.keys.sorted() {
            byPath[path.lowercased()] = path
            if known[path] == .markdown { byPath[String(path.dropLast(3)).lowercased()] = path }
            byName[Self.noteName(path).lowercased(), default: []].append(path)
        }
        func named(_ target: String, from folder: String) -> String? {
            let candidates = byName[Self.noteName(target).lowercased()] ?? []
            return candidates.first { ($0 as NSString).deletingLastPathComponent == folder } ?? candidates.first
        }
        var nodes: [MemoryGraph.Node] = []
        var edges = Set<MemoryGraph.Edge>()
        var links = Set<MemoryGraph.Link>()
        var projects = Set<String>()
        var indexes: [String: String] = [:]
        /// Links to nothing, in a vault: one node per name, titled as first written.
        var unresolved: [String: String] = [:]
        for path in paths {
            let entry = cache[path]
            let id = nodeID(forFile: path)
            if vault {
                nodes.append(MemoryGraph.Node(id: path, title: Self.noteName(path), kind: entry?.kind == .attachment ? .attachment : .note,
                                              project: nil, modified: entry?.modified, file: path))
            } else {
                let project = Self.project(of: path)
                if let project { projects.insert(project) }
                if let indexed = MemoryGraph.indexedProject(path) {
                    indexes[indexed] = path
                } else {
                    nodes.append(MemoryGraph.Node(id: path, title: Self.noteName(path), kind: .note, project: project,
                                                  modified: entry?.modified, file: path))
                    if let project { edges.insert(MemoryGraph.Edge("project:\(project)", path)) }
                }
            }
            let folder = (path as NSString).deletingLastPathComponent
            for target in entry?.targets ?? [] {
                var resolved: String?
                let written: String
                switch target {
                case .wiki(let name):
                    written = name
                    let key = name.lowercased()
                    resolved = byPath[key] ?? byPath[key + ".md"] ?? named(name, from: folder)
                case .markdown(let relative):
                    written = relative
                    let nearby = Self.collapse(folder.isEmpty ? relative : folder + "/" + relative)
                    let fromRoot = Self.collapse(relative)
                    resolved = nearby.flatMap { byPath[$0.lowercased()] } ?? fromRoot.flatMap { byPath[$0.lowercased()] }
                        ?? (relative.contains("..") ? nil : named(relative, from: folder))
                }
                let other: String
                if let resolved {
                    // A file that is not drawn (hidden, or left out by the cap): no line, and no link to nothing either.
                    guard cache[resolved] != nil else { continue }
                    other = nodeID(forFile: resolved)
                } else if vault {
                    other = "unresolved:" + written.lowercased()
                    if unresolved[other] == nil { unresolved[other] = written }
                } else {
                    continue
                }
                if other != id {
                    edges.insert(MemoryGraph.Edge(id, other))
                    links.insert(MemoryGraph.Link(source: id, target: other))
                }
            }
        }
        for project in projects.sorted() {
            let index = indexes[project]
            nodes.append(MemoryGraph.Node(id: "project:\(project)", title: project, kind: .project, project: project,
                                          modified: index.flatMap { cache[$0]?.modified }, file: index))
        }
        for (id, title) in unresolved.sorted(by: { $0.key < $1.key }) {
            nodes.append(MemoryGraph.Node(id: id, title: title, kind: .unresolved, project: nil, modified: nil, file: nil))
        }
        return MemoryGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) },
                           links: links.sorted { ($0.source, $0.target) < ($1.source, $1.target) })
    }
}
