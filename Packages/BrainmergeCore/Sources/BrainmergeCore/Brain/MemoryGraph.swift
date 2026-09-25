import Foundation

/// A memory folder seen as a graph, like Obsidian's graph view: every Markdown note is a node, every link between
/// two notes is an edge, and each project folder of Claude Code's memory (`memory/<project>/`) is a hub linked to
/// its notes. Only file names and note text are read; nothing is written.
public struct MemoryGraph: Equatable, Sendable {
    public struct Node: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable { case note, project }
        /// The note's path relative to the memory folder, or "project:<name>" for a hub.
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

    public enum LinkTarget: Equatable, Sendable {
        case wiki(String)
        case markdown(String)
    }

    public var nodes: [Node]
    public var edges: [Edge]
    public init(nodes: [Node] = [], edges: [Edge] = []) { self.nodes = nodes; self.edges = edges }

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
    public func degree(_ id: String) -> Int { edges.reduce(0) { $0 + ($1.from == id || $1.to == id ? 1 : 0) } }

    /// The project whose index a file is (`memory/<project>/MEMORY.md`), if it is one.
    static func indexedProject(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "memory" && parts[2] == "MEMORY.md" && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    /// The bubble a file is drawn as: a project's index is its project's bubble, any other note is its own.
    public static func nodeID(forFile path: String) -> String {
        indexedProject(path).map { "project:\($0)" } ?? path
    }

    /// Files a wikilink points at that are not notes: embedded images, documents, sounds, canvases.
    static let attachmentExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "bmp", "tif", "tiff", "avif",
                                                    "pdf", "mp3", "m4a", "wav", "ogg", "flac", "mp4", "mov", "webm", "mkv",
                                                    "canvas", "excalidraw", "base", "zip", "csv", "json"]

    /// The link targets written in a note: `[[target]]`, `[[target|alias]]`, `[[target#heading]]`, and Markdown links
    /// to local notes, `[text](path.md)`, `[text](<path with spaces.md>)`, `[text](path.md "title")`. Web and mail links,
    /// attachments, inline code and fenced code blocks are ignored. One pass, linear in the length of the text.
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
                let ext = (target as NSString).pathExtension.lowercased()
                if !target.isEmpty, !attachmentExtensions.contains(ext) { targets.append(.wiki(target)) }
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
                    if !target.isEmpty, !lower.contains(":"), lower.hasSuffix(".md") {
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
    }

    struct Entry { var modified: Date; var size: Int; var targets: [MemoryGraph.LinkTarget] }

    public let root: URL
    public let maxNotes: Int
    /// Bytes read per note at most: links sit in the text, and a huge note must not stall the build.
    public let maxBytes: Int
    private var cache: [String: Entry] = [:]
    private var built = false

    public init(root: URL, maxNotes: Int = 2000, maxBytes: Int = 256 * 1024) {
        // A memory kept in Dropbox or iCloud is often reached through a symlink: read the folder it points to, by its
        // real path, which is also how the enumerator spells the files it finds ("/private/var", not "/var").
        self.root = Self.realPath(root); self.maxNotes = maxNotes; self.maxBytes = maxBytes
    }

    static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.standardizedFileURL.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    static let skippedFolders: Set<String> = [".git", ".obsidian", ".brainmerge", ".trash", ".Trash", "node_modules", ".smart-connections"]

    /// The Markdown notes under the folder, as relative paths with their date and size. Hidden folders are skipped,
    /// and so are symlinks: a note always is a file of this folder, never something a link points to elsewhere.
    /// One `fts` walk that gets each file's date and size with its name: fifty thousand files take a fraction of a second.
    func scan() -> [(path: String, modified: Date, size: Int)] {
        var notes: [(String, Date, Int)] = []
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let start = strdup(root.path) else { return [] }
        defer { free(start) }
        var roots: [UnsafeMutablePointer<CChar>?] = [start, nil]
        // FTS_PHYSICAL: symlinks are reported as links and never followed.
        guard let fts = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return [] }
        defer { fts_close(fts) }
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            guard let cPath = entry.pointee.fts_path else { continue }
            let path = String(cString: cPath)
            let name = (path as NSString).lastPathComponent
            if info == FTS_D {
                if entry.pointee.fts_level > 0, Self.skippedFolders.contains(name) || name.hasPrefix(".") { fts_set(fts, entry, FTS_SKIP) }
                continue
            }
            guard info == FTS_F, !name.hasPrefix("."), name.lowercased().hasSuffix(".md"), path.hasPrefix(base),
                  let stat = entry.pointee.fts_statp?.pointee else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec) + TimeInterval(stat.st_mtimespec.tv_nsec) / 1e9)
            notes.append((String(path.dropFirst(base.count)), modified, Int(stat.st_size)))
        }
        return notes
    }

    public func build() -> Result {
        var files = scan()
        var truncated = false
        if files.count > maxNotes {
            truncated = true
            files = Array(files.sorted { $0.modified > $1.modified }.prefix(maxNotes))
        }
        var changed: [String] = []
        var read = 0
        var next: [String: Entry] = [:]
        for file in files {
            if let entry = cache[file.path], entry.modified == file.modified, entry.size == file.size {
                next[file.path] = entry
                continue
            }
            let text = readText(root.appending(path: file.path))
            read += 1
            next[file.path] = Entry(modified: file.modified, size: file.size, targets: MemoryGraph.linkTargets(in: text))
            changed.append(file.path)
        }
        let removed = cache.keys.filter { next[$0] == nil }
        cache = next
        built = true
        // Reported by bubble: a project's index that changed is its project's bubble that changed.
        let ids = { (paths: [String]) in Array(Set(paths.map(MemoryGraph.nodeID(forFile:)))).sorted() }
        return Result(graph: makeGraph(), changed: ids(changed), removed: ids(removed), readFiles: read, truncated: truncated)
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
    static func noteName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private func makeGraph() -> MemoryGraph {
        let paths = cache.keys.sorted()
        // Links resolve like Obsidian: an exact path first, then the note name anywhere, whatever the case,
        // preferring a note in the same folder.
        var byPath: [String: String] = [:]
        var byName: [String: [String]] = [:]
        for path in paths {
            byPath[path.lowercased()] = path
            byPath[String(path.dropLast(3)).lowercased()] = path
            byName[Self.noteName(path).lowercased(), default: []].append(path)
        }
        func named(_ target: String, from folder: String) -> String? {
            let candidates = byName[Self.noteName(target).lowercased()] ?? []
            return candidates.first { ($0 as NSString).deletingLastPathComponent == folder } ?? candidates.first
        }
        var nodes: [MemoryGraph.Node] = []
        var edges = Set<MemoryGraph.Edge>()
        var projects = Set<String>()
        var indexes: [String: String] = [:]
        for path in paths {
            let project = Self.project(of: path)
            if let project { projects.insert(project) }
            let id = MemoryGraph.nodeID(forFile: path)
            if let indexed = MemoryGraph.indexedProject(path) {
                indexes[indexed] = path
            } else {
                nodes.append(MemoryGraph.Node(id: path, title: Self.noteName(path), kind: .note, project: project,
                                              modified: cache[path]?.modified, file: path))
                if let project { edges.insert(MemoryGraph.Edge("project:\(project)", path)) }
            }
            let folder = (path as NSString).deletingLastPathComponent
            for target in cache[path]?.targets ?? [] {
                var resolved: String?
                switch target {
                case .wiki(let name):
                    let key = name.lowercased()
                    resolved = byPath[key] ?? byPath[key + ".md"] ?? named(name, from: folder)
                case .markdown(let relative):
                    let nearby = Self.collapse(folder.isEmpty ? relative : folder + "/" + relative)
                    let fromRoot = Self.collapse(relative)
                    resolved = nearby.flatMap { byPath[$0.lowercased()] } ?? fromRoot.flatMap { byPath[$0.lowercased()] }
                        ?? (relative.contains("..") ? nil : named(relative, from: folder))
                }
                if let resolved {
                    let other = MemoryGraph.nodeID(forFile: resolved)
                    if other != id { edges.insert(MemoryGraph.Edge(id, other)) }
                }
            }
        }
        for project in projects.sorted() {
            let index = indexes[project]
            nodes.append(MemoryGraph.Node(id: "project:\(project)", title: project, kind: .project, project: project,
                                          modified: index.flatMap { cache[$0]?.modified }, file: index))
        }
        return MemoryGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
    }
}
