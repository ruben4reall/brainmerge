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
        public init(id: String, title: String, kind: Kind, project: String?, modified: Date?) {
            self.id = id; self.title = title; self.kind = kind; self.project = project; self.modified = modified
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

    /// The link targets written in a note: `[[target]]`, `[[target|alias]]`, `[[target#heading]]`, and Markdown links
    /// to local files. Web and mail links are ignored, and so are wikilinks to anything but a note (images, PDFs).
    public static func linkTargets(in text: String) -> [LinkTarget] {
        var targets: [LinkTarget] = []
        let scalars = Array(text.unicodeScalars)
        var i = 0
        func string(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[range])) }
        while i < scalars.count {
            if scalars[i] == "[", i + 1 < scalars.count, scalars[i + 1] == "[" {
                let start = i + 2
                var j = start
                while j + 1 < scalars.count, !(scalars[j] == "]" && scalars[j + 1] == "]"), scalars[j] != "\n" { j += 1 }
                if j + 1 < scalars.count, scalars[j] == "]" {
                    var target = string(start..<j)
                    if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
                    if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
                    target = target.trimmingCharacters(in: .whitespaces)
                    let ext = (target as NSString).pathExtension.lowercased()
                    if !target.isEmpty, ext.isEmpty || ext == "md" { targets.append(.wiki(target)) }
                    i = j + 2
                    continue
                }
            }
            if scalars[i] == "]", i + 1 < scalars.count, scalars[i + 1] == "(" {
                let start = i + 2
                var j = start
                while j < scalars.count, scalars[j] != ")", scalars[j] != "\n", scalars[j] != " " { j += 1 }
                if j < scalars.count, scalars[j] == ")" {
                    var target = string(start..<j)
                    if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
                    let lower = target.lowercased()
                    if !target.isEmpty, !lower.contains(":"), lower.hasSuffix(".md") {
                        targets.append(.markdown(target.removingPercentEncoding ?? target))
                    }
                    i = j + 1
                    continue
                }
            }
            i += 1
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
        self.root = root.standardizedFileURL; self.maxNotes = maxNotes; self.maxBytes = maxBytes
    }

    static let skippedFolders: Set<String> = [".git", ".obsidian", ".brainmerge", ".trash", ".Trash", "node_modules", ".smart-connections"]

    /// The Markdown notes under the folder, as relative paths with their date and size. Hidden folders are skipped.
    func scan() -> [(path: String, modified: Date, size: Int)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return [] }
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var notes: [(String, Date, Int)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if Self.skippedFolders.contains(name) || name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", !name.hasPrefix(".") else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            notes.append((String(path.dropFirst(base.count)), values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0))
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
        let removed = cache.keys.filter { next[$0] == nil }.sorted()
        cache = next
        built = true
        return Result(graph: makeGraph(), changed: changed.sorted(), removed: removed, readFiles: read, truncated: truncated)
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

    private func makeGraph() -> MemoryGraph {
        let paths = cache.keys.sorted()
        // Wikilinks resolve like Obsidian: an exact path first, then the note name anywhere, whatever the case.
        var byPath: [String: String] = [:]
        var byName: [String: [String]] = [:]
        for path in paths {
            byPath[path.lowercased()] = path
            byPath[String(path.dropLast(3)).lowercased()] = path
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            byName[name, default: []].append(path)
        }
        var nodes: [MemoryGraph.Node] = []
        var edges = Set<MemoryGraph.Edge>()
        var projects = Set<String>()
        for path in paths {
            let project = Self.project(of: path)
            if let project { projects.insert(project) }
            let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            nodes.append(MemoryGraph.Node(id: path, title: title, kind: .note, project: project, modified: cache[path]?.modified))
            let folder = (path as NSString).deletingLastPathComponent
            for target in cache[path]?.targets ?? [] {
                var resolved: String?
                switch target {
                case .wiki(let name):
                    let key = name.lowercased()
                    if let exact = byPath[key] ?? byPath[key + ".md"] { resolved = exact }
                    else {
                        let base = ((key as NSString).lastPathComponent as NSString).deletingPathExtension
                        let candidates = byName[base] ?? []
                        resolved = candidates.first { ($0 as NSString).deletingLastPathComponent == folder } ?? candidates.first
                    }
                case .markdown(let relative):
                    let joined = folder.isEmpty ? relative : folder + "/" + relative
                    let normalized = (joined as NSString).standardizingPath
                    resolved = byPath[normalized.lowercased()]
                }
                if let resolved, resolved != path { edges.insert(MemoryGraph.Edge(path, resolved)) }
            }
            if let project { edges.insert(MemoryGraph.Edge("project:\(project)", path)) }
        }
        for project in projects.sorted() {
            nodes.append(MemoryGraph.Node(id: "project:\(project)", title: project, kind: .project, project: project, modified: nil))
        }
        return MemoryGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
    }
}
