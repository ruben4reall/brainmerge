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
    /// Saves read from the history to tell who saved each note last.
    nonisolated static let historyDepth = 5000

    public private(set) var graph = MemoryGraph()
    /// Who saved each bubble last, by bubble id (a project's index speaks for its project).
    public private(set) var authors: [String: Author] = [:]
    public private(set) var pulses: [String: Pulse] = [:]
    public private(set) var truncated = false
    public private(set) var lastChange: Date?
    public private(set) var root: URL?
    /// Bumped on every animation frame, so the canvas redraws while the graph moves.
    public private(set) var frame = 0
    /// How long the last read of the folder took: the screen waits longer between reads of a very large folder.
    public private(set) var lastRefreshDuration: TimeInterval = 0
    public var selected: String?
    public var hovered: String?
    /// An account picked in the legend: its notes stay lit, the others fade.
    public var highlightedAccount: String?
    public var camera = GraphCamera()
    /// The view has framed the graph once; later changes keep the person's own zoom and position.
    public var fitted = false
    /// With Reduce Motion on, the layout settles out of sight and appears in place, and pulses do not ripple.
    public var reduceMotion = false { didSet { if reduceMotion { settleQuietly() } else { animate() } } }

    /// Where the pointer is over the graph, and the graph's size on screen (read by the scroll-wheel handler).
    @ObservationIgnored public var pointer: CGPoint?
    @ObservationIgnored public var viewSize: CGSize = .zero
    /// How many times the history was read (observability: once per save, not once per refresh).
    @ObservationIgnored public private(set) var historyReads = 0
    /// The quiet settling in progress under Reduce Motion, if any.
    @ObservationIgnored public private(set) var settleTask: Task<Void, Never>?

    var layout = GraphLayout()
    @ObservationIgnored private var adjacency: [String: Set<String>] = [:]
    @ObservationIgnored private var builder: MemoryGraphBuilder?
    /// Bumped whenever the memory changes: a read started for the previous memory is thrown away when it ends.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reading: Int?
    @ObservationIgnored private var head: String?
    @ObservationIgnored private var layoutGeneration = 0
    @ObservationIgnored private var timer: Timer?
    private let animates: Bool
    @ObservationIgnored private var dragged: String?

    public init(animates: Bool = true) { self.animates = animates }

    /// Reads the folder again. The first read of a folder sets the scene without pulses; the next ones pulse what changed.
    /// Switching to another memory never waits for a read of the previous one: that read is discarded when it ends.
    public func refresh(root newRoot: URL?) async {
        guard let newRoot else { reset(nil); return }
        if newRoot.standardizedFileURL != root?.standardizedFileURL { reset(newRoot) }
        guard let builder, reading != generation else { return }
        let mine = generation
        reading = mine
        defer { if reading == mine { reading = nil } }
        let first = graph.nodes.isEmpty && authors.isEmpty
        let knownHead = head, knownAuthors = authors
        let started = Date()
        let (result, newHead, history, readHistory) = await Task.detached(priority: .utility) {
            () -> (MemoryGraphBuilder.Result, String?, [String: Author], Bool) in
            let result = builder.build()
            let brain = Brain(root: newRoot)
            guard FileManager.default.fileExists(atPath: brain.gitDir.path) else { return (result, nil, [:], false) }
            let git = BrainGit(brain: brain)
            let head = git.head()
            // The history only moves with a save: read it again then, not every few seconds.
            guard head != knownHead || head == nil && !knownAuthors.isEmpty else { return (result, head, knownAuthors, false) }
            var history: [String: Author] = [:]
            for (path, entry) in (try? git.lastAuthors(limit: MemoryGraphModel.historyDepth)) ?? [:] {
                let slug = entry.email.hasSuffix("@brainmerge.local") ? String(entry.email.dropLast("@brainmerge.local".count)) : nil
                let id = MemoryGraph.nodeID(forFile: path)
                if let known = history[id], known.date >= entry.date { continue }
                history[id] = Author(slug: slug, name: entry.name, date: entry.date)
            }
            return (result, head, history, true)
        }.value
        // Another memory was picked meanwhile, or the screen went away: this read no longer matters.
        guard mine == generation, !Task.isCancelled else { return }
        lastRefreshDuration = Date().timeIntervalSince(started)
        head = newHead
        if readHistory { historyReads += 1 }
        let now = Date()
        if !first {
            for id in result.changed { pulses[id] = Pulse(start: now, slug: nil) }
            for (id, author) in history where authors[id] != author && result.graph.node(id) != nil {
                pulses[id] = Pulse(start: now, slug: author.slug)
            }
            if !result.changed.isEmpty || pulses.values.contains(where: { $0.start == now }) { lastChange = now }
        }
        if history != authors { authors = history }
        if truncated != result.truncated { truncated = result.truncated }
        if result.graph != graph {
            graph = result.graph
            var adjacency: [String: Set<String>] = [:]
            for edge in graph.edges { adjacency[edge.from, default: []].insert(edge.to); adjacency[edge.to, default: []].insert(edge.from) }
            self.adjacency = adjacency
            layout.sync(nodes: graph.nodes.map(\.id), edges: graph.edges.map { ($0.from, $0.to) })
            layoutGeneration += 1
            if let selected, graph.node(selected) == nil { self.selected = nil }
            if let hovered, graph.node(hovered) == nil { self.hovered = nil }
        }
        if let slug = highlightedAccount, !authors.contains(where: { $0.value.slug == slug && graph.node($0.key) != nil }) {
            highlightedAccount = nil
        }
        if reduceMotion { settleQuietly() }
        animate()
    }

    private func reset(_ newRoot: URL?) {
        generation += 1
        root = newRoot
        builder = newRoot.map { MemoryGraphBuilder(root: $0) }
        graph = MemoryGraph(); authors = [:]; pulses = [:]; layout = GraphLayout(); adjacency = [:]; head = nil
        layoutGeneration += 1
        selected = nil; hovered = nil; highlightedAccount = nil; fitted = false; lastChange = nil
    }

    public func clearPulses() { pulses = [:] }

    /// The pointer left the graph, or the graph left the screen.
    public func pointerLeft() { pointer = nil; hovered = nil }

    public func neighbors(of id: String) -> Set<String> { adjacency[id] ?? [] }

    /// The bubbles an account saved last, with the projects they belong to.
    public func notes(savedBy slug: String) -> Set<String> {
        var ids = Set<String>()
        for (id, author) in authors where author.slug == slug && graph.node(id) != nil {
            ids.insert(id)
            for other in adjacency[id] ?? [] where other.hasPrefix("project:") { ids.insert(other) }
        }
        return ids
    }

    /// The file behind a bubble (a note, or a project's index), or the project's folder when it has no index.
    /// Always inside the memory folder.
    public func fileURL(_ id: String) -> URL? {
        guard let root else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let url: URL
        if let file = graph.node(id)?.file {
            url = root.appending(path: file)
        } else if id.hasPrefix("project:") {
            url = root.appending(path: "memory/\(id.dropFirst("project:".count))", directoryHint: .isDirectory)
        } else {
            url = root.appending(path: id)
        }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        return resolved.path.hasPrefix(base.path + "/") ? resolved : nil
    }

    /// The first lines of a note, without its frontmatter, for the inspector. Read off the main thread.
    public func loadPreview(_ id: String, lines: Int = 14) async -> String {
        guard graph.node(id)?.file != nil, let url = fileURL(id) else { return "" }
        return await Task.detached(priority: .userInitiated) { Self.readPreview(url, lines: lines) }.value
    }

    nonisolated static func readPreview(_ url: URL, lines: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var text = String(decoding: (try? handle.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self)
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            text = String(text[end.upperBound...])
        }
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(lines)
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Brings a bubble to the center when it is out of view (keyboard and VoiceOver selection).
    public func reveal(_ id: String) {
        guard let p = layout.position(of: id), viewSize != .zero else { return }
        let s = camera.toScreen(p, in: viewSize)
        let margin: CGFloat = 80
        if s.x < margin || s.y < margin || s.x > viewSize.width - margin || s.y > viewSize.height - margin {
            camera.center = p
            fitted = true
        }
    }

    // MARK: Motion

    public var isMoving: Bool { (!layout.isSettled && !reduceMotion) || !pulses.isEmpty || dragged != nil }

    public func position(of id: String) -> CGPoint? { layout.position(of: id) }

    public func drag(_ id: String, to point: CGPoint) { dragged = id; layout.drag(id, to: point); layoutGeneration += 1; animate() }
    public func endDrag() {
        if let dragged { layout.release(dragged) }
        dragged = nil; layoutGeneration += 1
        if reduceMotion { settleQuietly() }
        animate()
    }

    /// Runs the simulation at the display's pace while something moves, and stops when everything is still.
    func animate() {
        guard animates, timer == nil, isMoving else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Under Reduce Motion: runs the simulation to rest off the main thread, then shows the result in one go.
    /// A change made meanwhile (a new note, a drag) starts it again from the new state.
    func settleQuietly() {
        guard reduceMotion, settleTask == nil, dragged == nil, layout.count > 0, !layout.isSettled else { return }
        let start = layout, mine = layoutGeneration
        settleTask = Task { [weak self] in
            let settled = await Task.detached(priority: .userInitiated) { () -> GraphLayout in
                var layout = start
                var steps = 0
                while !layout.isSettled, steps < 1000 { layout.step(); steps += 1 }
                return layout
            }.value
            guard let self else { return }
            self.settleTask = nil
            guard mine == self.layoutGeneration else { self.settleQuietly(); return }
            self.layout = settled
            if !self.fitted, self.viewSize != .zero { self.camera.fit(settled.bounds, in: self.viewSize); self.fitted = true }
            self.frame &+= 1
        }
    }

    /// Frames the whole graph now.
    public func fitNow() {
        guard layout.count > 0, viewSize != .zero else { return }
        camera.fit(layout.bounds, in: viewSize)
    }

    func tick() {
        if dragged != nil || (!reduceMotion && !layout.isSettled) { layout.step() }
        // Until the person moves around, the camera follows the graph as it unfolds.
        if !fitted, !reduceMotion, layout.count > 0, viewSize != .zero {
            camera.fit(layout.bounds, in: viewSize)
            if layout.isSettled { fitted = true }
        }
        let now = Date()
        if !pulses.isEmpty { pulses = pulses.filter { now.timeIntervalSince($0.value.start) < Self.pulseDuration } }
        frame &+= 1
        if !isMoving { timer?.invalidate(); timer = nil }
    }

    /// Stops the animation (the screen went away). It starts again with the next change.
    public func stop() { timer?.invalidate(); timer = nil }
}
