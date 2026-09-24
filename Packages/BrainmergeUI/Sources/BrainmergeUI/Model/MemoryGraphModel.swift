import AppKit
import Foundation
import Observation
import BrainmergeCore

/// Where the graph is looked at from: the world point at the center of the view, and the zoom.
public struct GraphCamera: Equatable, Sendable {
    public static let minScale: CGFloat = 0.15
    public static let maxScale: CGFloat = 4
    public var center: CGPoint = .zero
    public var scale: CGFloat = 1
    public init() {}

    public func toScreen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - center.x) * scale + size.width / 2, y: (p.y - center.y) * scale + size.height / 2)
    }
    public func toWorld(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2) / scale + center.x, y: (p.y - size.height / 2) / scale + center.y)
    }
    /// Frames a rectangle of the world in the view, with a margin.
    public mutating func fit(_ rect: CGRect, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        center = CGPoint(x: rect.midX, y: rect.midY)
        let w = max(rect.width, 80), h = max(rect.height, 80)
        scale = min(max(min(size.width / w, size.height / h) * 0.82, Self.minScale), Self.maxScale)
    }
    /// Zooms while keeping the world point under the pointer where it is.
    public mutating func zoom(by factor: CGFloat, around pointer: CGPoint, in size: CGSize) {
        let anchor = toWorld(pointer, in: size)
        scale = min(max(scale * factor, Self.minScale), Self.maxScale)
        center = CGPoint(x: anchor.x - (pointer.x - size.width / 2) / scale, y: anchor.y - (pointer.y - size.height / 2) / scale)
    }
    public mutating func pan(by delta: CGSize) {
        center = CGPoint(x: center.x - delta.width / scale, y: center.y - delta.height / scale)
    }
}

/// The live graph of a memory folder, for the Memory screen: rebuilt every couple of seconds from the files
/// (only changed notes are read), laid out by a force simulation, with a pulse on every note that is being
/// written or has just been saved by an account.
@MainActor @Observable
public final class MemoryGraphModel {
    public struct Author: Equatable, Sendable {
        /// The account's slug when a Brainmerge account saved it, nil for anyone else (a person editing in Obsidian).
        public let slug: String?
        public let name: String
        public let date: Date
    }
    public struct Pulse: Equatable, Sendable {
        public let start: Date
        /// The account that saved the note, nil while it is being written and not saved yet.
        public let slug: String?
    }
    public static let pulseDuration: TimeInterval = 2.6

    public private(set) var graph = MemoryGraph()
    public private(set) var authors: [String: Author] = [:]
    public private(set) var pulses: [String: Pulse] = [:]
    public private(set) var truncated = false
    public private(set) var lastChange: Date?
    public private(set) var root: URL?
    /// Bumped on every animation frame, so the canvas redraws while the graph moves.
    public private(set) var frame = 0
    public var selected: String?
    public var hovered: String?
    /// An account picked in the legend: its notes stay lit, the others fade.
    public var highlightedAccount: String?
    public var camera = GraphCamera()
    /// The view has framed the graph once; later changes keep the person's own zoom and position.
    public var fitted = false

    /// Where the pointer is over the graph, and the graph's size on screen (read by the scroll-wheel handler).
    @ObservationIgnored public var pointer: CGPoint?
    @ObservationIgnored public var viewSize: CGSize = .zero

    var layout = GraphLayout()
    private var builder: MemoryGraphBuilder?
    private var refreshing = false
    private var timer: Timer?
    private let animates: Bool
    private var dragged: String?

    public init(animates: Bool = true) { self.animates = animates }

    /// Reads the folder again. The first read of a folder sets the scene without pulses; the next ones pulse what changed.
    public func refresh(root newRoot: URL?) async {
        guard !refreshing else { return }
        guard let newRoot else { reset(nil); return }
        if newRoot.standardizedFileURL != root?.standardizedFileURL { reset(newRoot) }
        guard let builder else { return }
        refreshing = true
        defer { refreshing = false }
        let first = graph.nodes.isEmpty && authors.isEmpty
        let (result, history): (MemoryGraphBuilder.Result, [String: Author]) = await Task.detached(priority: .utility) {
            let result = builder.build()
            var history: [String: Author] = [:]
            let brain = Brain(root: newRoot)
            if FileManager.default.fileExists(atPath: brain.gitDir.path),
               let last = try? BrainGit(brain: brain).lastAuthors(limit: 1500) {
                for (path, entry) in last {
                    let slug = entry.email.hasSuffix("@brainmerge.local") ? String(entry.email.dropLast("@brainmerge.local".count)) : nil
                    history[path] = Author(slug: slug, name: entry.name, date: entry.date)
                }
            }
            return (result, history)
        }.value
        guard newRoot.standardizedFileURL == root?.standardizedFileURL else { return }   // the memory changed meanwhile
        let now = Date()
        if !first {
            for path in result.changed { pulses[path] = Pulse(start: now, slug: nil) }
            for (path, author) in history where authors[path] != author && result.graph.node(path) != nil {
                pulses[path] = Pulse(start: now, slug: author.slug)
            }
            if !result.changed.isEmpty || pulses.values.contains(where: { $0.start == now }) { lastChange = now }
        }
        authors = history
        truncated = result.truncated
        if result.graph != graph {
            graph = result.graph
            layout.sync(nodes: graph.nodes.map(\.id), edges: graph.edges.map { ($0.from, $0.to) })
            if let selected, graph.node(selected) == nil { self.selected = nil }
        }
        animate()
    }

    private func reset(_ newRoot: URL?) {
        root = newRoot
        builder = newRoot.map { MemoryGraphBuilder(root: $0) }
        graph = MemoryGraph(); authors = [:]; pulses = [:]; layout = GraphLayout()
        selected = nil; hovered = nil; highlightedAccount = nil; fitted = false; lastChange = nil
    }

    public func clearPulses() { pulses = [:] }

    public func neighbors(of id: String) -> Set<String> {
        var result = Set<String>()
        for edge in graph.edges {
            if edge.from == id { result.insert(edge.to) } else if edge.to == id { result.insert(edge.from) }
        }
        return result
    }

    /// The note's file, or the project's folder for a hub.
    public func fileURL(_ id: String) -> URL? {
        guard let root else { return nil }
        if id.hasPrefix("project:") { return root.appending(path: "memory/\(id.dropFirst("project:".count))", directoryHint: .isDirectory) }
        return root.appending(path: id)
    }

    /// The first lines of a note, without its frontmatter, for the inspector.
    public func preview(_ id: String, lines: Int = 14) -> String {
        guard !id.hasPrefix("project:"), let url = fileURL(id), let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var text = String(decoding: (try? handle.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self)
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            text = String(text[end.upperBound...])
        }
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(lines)
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Motion

    public var isMoving: Bool { !layout.isSettled || !pulses.isEmpty || dragged != nil }

    public func position(of id: String) -> CGPoint? { layout.position(of: id) }

    public func drag(_ id: String, to point: CGPoint) { dragged = id; layout.drag(id, to: point); animate() }
    public func endDrag() { if let dragged { layout.release(dragged) }; dragged = nil; animate() }

    /// Runs the simulation at the display's pace while something moves, and stops when everything is still.
    func animate() {
        guard animates, timer == nil, isMoving else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Frames the whole graph now.
    public func fitNow() {
        guard layout.count > 0, viewSize != .zero else { return }
        camera.fit(layout.bounds, in: viewSize)
    }

    func tick() {
        if !layout.isSettled || dragged != nil { layout.step() }
        // Until the person moves around, the camera follows the graph as it unfolds.
        if !fitted, layout.count > 0, viewSize != .zero {
            camera.fit(layout.bounds, in: viewSize)
            if layout.isSettled { fitted = true }
        }
        let now = Date()
        if !pulses.isEmpty { pulses = pulses.filter { now.timeIntervalSince($0.value.start) < Self.pulseDuration } }
        frame &+= 1
        if !isMoving { timer?.invalidate(); timer = nil }
    }

    public func stop() { timer?.invalidate(); timer = nil }
}
