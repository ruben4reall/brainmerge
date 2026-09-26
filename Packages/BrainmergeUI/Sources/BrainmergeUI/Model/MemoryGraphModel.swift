import AppKit
import Foundation
import Observation
import BrainmergeCore

/// Where the graph is looked at from: the world point at the center of the view, and the zoom.
public struct GraphCamera: Equatable, Sendable {
    public static let minScale: CGFloat = 0.15
    public static let maxScale: CGFloat = 4
    /// Obsidian's zoom limits, for a vault.
    public static let obsidianZoom: ClosedRange<CGFloat> = (1.0 / 128)...8
    public var center: CGPoint = .zero
    public var scale: CGFloat = 1
    /// Points per world unit at zoom 1. A vault is laid out in Obsidian's units, the screen's pixels: half a point on
    /// a Retina screen, so that Obsidian's saved zoom shows a vault the same size in both apps.
    public var unit: CGFloat = 1
    public var zoomRange: ClosedRange<CGFloat> = GraphCamera.minScale...GraphCamera.maxScale
    public init() {}

    /// Points per world unit now.
    var factor: CGFloat { scale * unit }

    public func toScreen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - center.x) * factor + size.width / 2, y: (p.y - center.y) * factor + size.height / 2)
    }
    public func toWorld(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2) / factor + center.x, y: (p.y - size.height / 2) / factor + center.y)
    }
    func clamped(_ value: CGFloat) -> CGFloat { min(max(value, zoomRange.lowerBound), zoomRange.upperBound) }
    /// Frames a rectangle of the world in the view, with a margin, between the strips `top` and `bottom` points high that
    /// the view's chrome covers (the legend, the status and the controls float there).
    public mutating func fit(_ rect: CGRect, in size: CGSize, top: CGFloat = 0, bottom: CGFloat = 0) {
        guard size.width > 0, size.height > 0 else { return }
        let height = max(1, size.height - top - bottom)
        let w = max(rect.width, 80), h = max(rect.height, 80)
        scale = clamped(min(size.width / w, height / h) * 0.82 / unit)
        center = CGPoint(x: rect.midX, y: rect.midY - (top - bottom) / 2 / factor)
    }
    /// Zooms while keeping the world point under the pointer where it is.
    public mutating func zoom(by factor: CGFloat, around pointer: CGPoint, in size: CGSize) {
        let anchor = toWorld(pointer, in: size)
        scale = clamped(scale * factor)
        center = CGPoint(x: anchor.x - (pointer.x - size.width / 2) / self.factor, y: anchor.y - (pointer.y - size.height / 2) / self.factor)
    }
    public mutating func pan(by delta: CGSize) {
        center = dragged(from: center, by: delta)
    }
    /// Where the center goes when the background is dragged by a distance on screen from where it was.
    public func dragged(from origin: CGPoint, by translation: CGSize) -> CGPoint {
        CGPoint(x: origin.x - translation.width / factor, y: origin.y - translation.height / factor)
    }
}

/// What the Memory screen's graph shows: a folder, and whether it is a Brainmerge memory or an Obsidian vault.
public struct GraphTarget: Equatable, Sendable {
    public let root: URL?
    public let style: MemoryGraph.Style
    public init(root: URL?, style: MemoryGraph.Style) { self.root = root?.standardizedFileURL; self.style = style }
    /// Changes whenever the graph must start over.
    public var key: String { "\(style.rawValue):\(root?.path ?? "")" }
}

/// The live graph of a memory folder, for the Memory screen: rebuilt every couple of seconds from the files
/// (only changed notes are read), laid out by a force simulation, with a pulse on every note that is being
/// written or has just been saved by an account. An Obsidian vault is drawn as Obsidian draws it instead: its own
/// filters, groups, forces and zoom from its graph settings, no hubs, no accounts, no pulses.
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
    /// A pulse lasts as long as its halo (see GraphPulse).
    public static let pulseDuration: TimeInterval = GraphPulse.halo
    /// How far Obsidian fades what is unrelated to the hovered note.
    public static let fadedAlpha = 0.2
    /// How far a memory fades what is unrelated, and its threads.
    public static let memoryDimmed = 0.28
    public static let memoryThreadsDimmed = 0.5
    /// Moving from one bubble to the next crosses empty space: the focus holds this long, so the graph never relights.
    public static let hoverGrace = 0.08
    /// Saves read from the history to tell who saved each note last.
    nonisolated static let historyDepth = 5000

    public private(set) var graph = MemoryGraph()
    public private(set) var style: MemoryGraph.Style = .memory
    /// A vault's graph settings, read from its `.obsidian` folder and read again when they change.
    public private(set) var settings = ObsidianGraphSettings()
    /// A vault's color group of each node that matched one.
    public private(set) var groupColors: [String: ObsidianGraphSettings.GroupColor] = [:]
    /// Obsidian's weight of each node (links in and out), which sets its size in a vault.
    public private(set) var weights: [String: Int] = [:]
    /// The lines drawn, by layout index: one per pair of linked notes, even when a vault's link goes both ways.
    public private(set) var lineIndices: [(Int, Int)] = []
    /// A vault's links with their direction, by layout index, for its arrows.
    public private(set) var arrowIndices: [(Int, Int)] = []
    /// Who saved each bubble last, by bubble id (a project's index speaks for its project).
    public private(set) var authors: [String: Author] = [:]
    public private(set) var pulses: [String: Pulse] = [:]
    public private(set) var truncated = false
    /// The folder could not be opened: macOS (or its permissions) refused. Said so instead of an empty graph.
    public private(set) var refused = false
    public private(set) var lastChange: Date?
    public private(set) var root: URL?
    /// Bumped on every animation frame, so the canvas redraws while the graph moves.
    public private(set) var frame = 0
    /// How long the last read of the folder took: the screen waits longer between reads of a very large folder.
    public private(set) var lastRefreshDuration: TimeInterval = 0
    public var selected: String? { didSet { if selected != oldValue { focusChanged() } } }
    public var hovered: String? { didSet { if hovered != oldValue { focusChanged() } } }
    /// An account picked in the legend: its notes stay lit, the others fade.
    public var highlightedAccount: String? { didSet { if highlightedAccount != oldValue { focusChanged() } } }
    public var camera = GraphCamera()
    /// The screen's pixels per point (2 on Retina): a vault is drawn in Obsidian's units, which are pixels.
    public var backingScale: CGFloat = 2 { didSet { if style == .vault { camera.unit = 1 / max(backingScale, 1) } } }
    /// The view has framed the graph once; later changes keep the person's own zoom and position.
    public var fitted = false
    /// With Reduce Motion on, the layout settles out of sight and appears in place, and pulses do not ripple.
    public var reduceMotion = false { didSet { if reduceMotion { settleQuietly() } else { animate() } } }
    /// The first read of a memory blooms from its hubs once its layout has settled out of sight (see GraphBloom); nothing
    /// is drawn until then. With Reduce Motion, and in captures, it appears in place once settled instead.
    private(set) var bloom: GraphBloom?
    public private(set) var awaitingFirstLayout = false
    /// The folder has been read once: until then the screen says nothing about it (not "No notes yet", not "0 notes").
    public private(set) var hasRead = false
    /// What the view's chrome covers, in points: the legend on top (a memory's), the status and the controls at the bottom.
    public nonisolated static let chromeTop: CGFloat = 36, chromeBottom: CGFloat = 40
    var chrome: (top: CGFloat, bottom: CGFloat) { (style == .vault ? 0 : Self.chromeTop, Self.chromeBottom) }
    /// When the first layout appeared in place (Reduce Motion): the graph fades in over 0.15 s from here.
    public private(set) var revealedAt: Date?
    /// The settling before the bloom, off the main thread.
    @ObservationIgnored public private(set) var bloomTask: Task<Void, Never>?
    /// The zoom buttons and Fit glide (see CameraTween); the camera it last set, to see a gesture move it meanwhile.
    @ObservationIgnored private var cameraTween: CameraTween?
    @ObservationIgnored private var tweenCamera: GraphCamera?
    @ObservationIgnored private var hoverGraceTask: Task<Void, Never>?
    /// The time of every frame, injectable in tests.
    @ObservationIgnored public var clock: @Sendable () -> Date = { Date() }

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
    private let blooms: Bool
    private let maxNotes: Int
    @ObservationIgnored private var dragged: String?
    /// In a vault, how visible each node is (eased toward 1, or a fifth when unrelated to the hovered one), and the lines.
    @ObservationIgnored private var fades: [String: Double] = [:]
    @ObservationIgnored public private(set) var lineFade = 1.0
    /// The last notes in focus: their threads stay lit while they fade back after the focus goes.
    @ObservationIgnored public private(set) var lastFocus: Set<String>?
    @ObservationIgnored private var fading = false
    /// The settings files as last read, to read them again only when they change.
    @ObservationIgnored private var settingsStamp: String?

    public init(animates: Bool = true, maxNotes: Int = 2000, blooms: Bool? = nil) {
        self.animates = animates; self.maxNotes = maxNotes; self.blooms = blooms ?? animates
    }

    /// Reads the folder again. The first read of a folder sets the scene without pulses; the next ones pulse what changed.
    /// Switching to another memory never waits for a read of the previous one: that read is discarded when it ends.
    public func refresh(root newRoot: URL?, style newStyle: MemoryGraph.Style = .memory) async {
        guard let newRoot else { reset(nil, style: newStyle); return }
        if newRoot.standardizedFileURL != root?.standardizedFileURL || newStyle != style { reset(newRoot, style: newStyle) }
        guard let builder, reading != generation else { return }
        let mine = generation
        reading = mine
        defer { if reading == mine { reading = nil } }
        let first = graph.nodes.isEmpty && authors.isEmpty && settingsStamp == nil
        let knownHead = head, knownAuthors = authors
        let style = self.style, knownStamp = settingsStamp, knownSettings = settings
        let started = Date()
        let (result, newHead, history, readHistory, vault) = await Task.detached(priority: .utility) {
            () -> (MemoryGraphBuilder.Result, String?, [String: Author], Bool, VaultRead?) in
            if style == .vault {
                // A vault is never asked who saved what: its look comes from its own settings, read again when they change,
                // and read first: the files they hide are not read, nor counted against the cap.
                let stamp = ObsidianGraphSettings.stamp(vault: newRoot)
                let settings = stamp == knownStamp ? knownSettings : ObsidianGraphSettings.read(vault: newRoot)
                let result = builder.build(showing: ObsidianGraphFilter.showsFile(settings))
                return (result, nil, [:], false, VaultRead(stamp: stamp, settings: settings, shown: ObsidianGraphFilter.apply(settings, to: result.graph)))
            }
            let result = builder.build()
            let brain = Brain(root: newRoot)
            guard FileManager.default.fileExists(atPath: brain.gitDir.path) else { return (result, nil, [:], false, nil) }
            let git = BrainGit(brain: brain)
            let head = git.head()
            // The history only moves with a save: read it again then, not every few seconds.
            guard head != knownHead || head == nil && !knownAuthors.isEmpty else { return (result, head, knownAuthors, false, nil) }
            var history: [String: Author] = [:]
            for (path, entry) in (try? git.lastAuthors(limit: MemoryGraphModel.historyDepth)) ?? [:] {
                let slug = MemoryFeed.accountSlug(entry.email)
                let id = MemoryGraph.nodeID(forFile: path)
                if let known = history[id], known.date >= entry.date { continue }
                history[id] = Author(slug: slug, name: entry.name, date: entry.date)
            }
            return (result, head, history, true, nil)
        }.value
        // Another memory was picked meanwhile, or the screen went away: this read no longer matters.
        guard mine == generation, !Task.isCancelled else { return }
        lastRefreshDuration = Date().timeIntervalSince(started)
        head = newHead
        if readHistory { historyReads += 1 }
        let now = clock()
        let shown = vault?.shown.graph ?? result.graph
        if let vault {
            settingsStamp = vault.stamp
            // The first read sets Obsidian's saved zoom; later ones only a new look: Obsidian saves its zoom every couple
            // of seconds while its graph is open, which must not pull the view away from the person.
            if first || !vault.settings.sameLook(as: settings) {
                settings = vault.settings
                layout.setForces(.obsidian(vault.settings))
                layoutGeneration += 1
            }
            if first {
                camera.center = .zero
                camera.scale = camera.clamped(CGFloat(vault.settings.scale))
                fitted = true
            }
            if groupColors != vault.shown.colors { groupColors = vault.shown.colors }
            if !first, result.changed.contains(where: { shown.node($0) != nil }) || result.removed.contains(where: { graph.node($0) != nil }) {
                lastChange = now
            }
        } else if !first {
            for id in result.changed { pulses[id] = Pulse(start: now, slug: nil) }
            for (id, author) in history where authors[id] != author && result.graph.node(id) != nil {
                pulses[id] = Pulse(start: now, slug: author.slug)
            }
            if !result.changed.isEmpty || pulses.values.contains(where: { $0.start == now }) { lastChange = now }
        }
        if history != authors { authors = history }
        // Only what the vault shows is counted: its hidden files never cut the graph short.
        let cut = result.truncated || result.attachmentsTruncated
        if truncated != cut { truncated = cut }
        if refused != result.refused { refused = result.refused }
        if shown != graph {
            graph = shown
            var adjacency: [String: Set<String>] = [:]
            for edge in graph.edges { adjacency[edge.from, default: []].insert(edge.to); adjacency[edge.to, default: []].insert(edge.from) }
            self.adjacency = adjacency
            // A vault's springs are its links, both ways when written both ways, as in Obsidian; a memory's are its lines.
            let springs = style == .vault ? graph.links.map { ($0.source, $0.target) } : graph.edges.map { ($0.from, $0.to) }
            layout.sync(nodes: graph.nodes.map(\.id), edges: springs)
            lineIndices = graph.edges.compactMap { edge in layout.indexOf(edge.from).flatMap { a in layout.indexOf(edge.to).map { (a, $0) } } }
            arrowIndices = style == .vault
                ? graph.links.compactMap { link in layout.indexOf(link.source).flatMap { a in layout.indexOf(link.target).map { (a, $0) } } } : []
            weights = style == .vault ? graph.weights() : [:]
            if !fades.isEmpty { let ids = Set(graph.nodes.map(\.id)); fades = fades.filter { ids.contains($0.key) } }
            layoutGeneration += 1
            // Its indices are the layout's: a graph that changed while it plays shows at once.
            bloom = nil
            if let selected, graph.node(selected) == nil { self.selected = nil }
            if let hovered, graph.node(hovered) == nil { self.hovered = nil }
        }
        if let slug = highlightedAccount, !authors.contains(where: { $0.value.slug == slug && graph.node($0.key) != nil }) {
            highlightedAccount = nil
        }
        if first, style == .memory, !graph.nodes.isEmpty {
            if quiet { awaitingFirstLayout = true; settleQuietly() } else if blooms { prepareBloom() }
        }
        if !hasRead { hasRead = true }
        if reduceMotion { settleQuietly() }
        animate()
    }

    /// Nothing moves on screen: Reduce Motion, or a capture, which shows each scene's end.
    private var quiet: Bool { reduceMotion || Theme.Motion.isCapture }

    /// The first read of a memory: its layout settles out of sight until nearly still, the camera frames it once, then the
    /// notes bloom out of their hubs while the rest settles live (about a second).
    private func prepareBloom() {
        guard bloomTask == nil, layout.count > 0 else { return }
        awaitingFirstLayout = true
        let start = layout, mine = layoutGeneration
        bloomTask = Task { [weak self] in
            let settled = await Task.detached(priority: .userInitiated) { () -> GraphLayout in
                var layout = start
                var steps = 0
                while layout.alpha >= MemoryGraphModel.bloomAlpha, steps < 1000 { layout.step(); steps += 1 }
                return layout
            }.value
            guard let self else { return }
            self.bloomTask = nil
            self.awaitingFirstLayout = false
            // The graph changed meanwhile: it shows live instead.
            guard mine == self.layoutGeneration else { self.animate(); return }
            self.layout = settled
            if self.viewSize != .zero { self.camera.fit(settled.bounds, in: self.viewSize, top: self.chrome.top, bottom: self.chrome.bottom) }
            self.fitted = true
            self.bloom = GraphBloom(ids: settled.ids, links: settled.linkIndices, positions: (0..<settled.count).map(settled.position(at:)),
                                    start: self.clock())
            self.frame &+= 1
            self.animate()
        }
    }
    /// How still the layout is when the bloom starts: what remains settles live, in about a second (at 0.05 it crept on
    /// for three).
    nonisolated static let bloomAlpha = 0.02

    /// Where a note is drawn now: on its way out of its hub while the bloom plays, else where the layout has it.
    public func drawnPosition(at i: Int, now: Date) -> CGPoint {
        let target = layout.position(at: i)
        guard let bloom, i < bloom.origins.count else { return target }
        return bloom.position(i, target: target, elapsed: Beat.elapsed(since: bloom.start, at: now) ?? 0)
    }
    /// How visible a note and a thread are while the bloom plays (1 otherwise).
    public func bloomOpacity(at i: Int, now: Date) -> Double {
        guard let bloom, i < bloom.origins.count else { return 1 }
        return bloom.opacity(i, elapsed: Beat.elapsed(since: bloom.start, at: now) ?? 0)
    }
    public func threadOpacity(_ a: Int, _ b: Int, now: Date) -> Double {
        guard let bloom, a < bloom.origins.count, b < bloom.origins.count else { return 1 }
        return bloom.edgeOpacity(a, b, elapsed: Beat.elapsed(since: bloom.start, at: now) ?? 0)
    }

    private func reset(_ newRoot: URL?, style newStyle: MemoryGraph.Style) {
        generation += 1
        root = newRoot
        style = newStyle
        builder = newRoot.map { MemoryGraphBuilder(root: $0, style: newStyle, maxNotes: maxNotes) }
        graph = MemoryGraph(); authors = [:]; pulses = [:]; layout = GraphLayout(); adjacency = [:]; head = nil
        settings = ObsidianGraphSettings(); settingsStamp = nil; groupColors = [:]; weights = [:]; lineIndices = []; arrowIndices = []
        fades = [:]; lineFade = 1; fading = false
        bloomTask?.cancel(); bloomTask = nil; bloom = nil; awaitingFirstLayout = false; revealedAt = nil; hasRead = false
        cameraTween = nil; tweenCamera = nil; hoverGraceTask?.cancel(); hoverGraceTask = nil
        var camera = GraphCamera()
        if newStyle == .vault { camera.unit = 1 / max(backingScale, 1); camera.zoomRange = GraphCamera.obsidianZoom }
        self.camera = camera
        layoutGeneration += 1
        selected = nil; hovered = nil; highlightedAccount = nil; fitted = false; lastChange = nil; truncated = false; refused = false
    }

    public func clearPulses() { pulses = [:] }

    /// The pointer left the graph, or the graph left the screen.
    public func pointerLeft() { hoverGraceTask?.cancel(); hoverGraceTask = nil; pointer = nil; hovered = nil }

    /// The bubble under the pointer as it moves. Leaving a bubble of a memory keeps its focus for `hoverGrace`: moving on
    /// to the next one never relights the graph in between. The grace counts from the moment the pointer left: moving on
    /// over empty space does not start it again. A vault follows Obsidian: at once.
    public func hover(_ id: String?) {
        if id == nil, hoverGraceTask != nil { return }
        hoverGraceTask?.cancel(); hoverGraceTask = nil
        guard id == nil, hovered != nil, style == .memory, !reduceMotion else {
            if hovered != id { hovered = id }
            return
        }
        hoverGraceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hoverGrace * Theme.Motion.slow))
            guard !Task.isCancelled, let self else { return }
            self.hoverGraceTask = nil
            self.hovered = nil
        }
    }

    public func neighbors(of id: String) -> Set<String> { adjacency[id] ?? [] }

    /// The bubble under a point of the view: within a finger's width of its center, and in a vault anywhere on the node
    /// as drawn (Obsidian's reach: its size plus 2), however large the zoom makes it.
    public func node(at point: CGPoint, in size: CGSize) -> String? {
        let world = camera.toWorld(point, in: size), factor = camera.factor
        guard style == .vault else { return layout.nearest(to: world, within: 14 / factor) }
        // Drawn at its size times the square root of the zoom, in Obsidian's units: in layout units, size / sqrt(zoom).
        let root = max(camera.scale.squareRoot(), .ulpOfOne), multiplier = settings.nodeSizeMultiplier
        let ids = layout.ids, weights = self.weights
        return layout.nearest(to: world, within: 14 / factor, margin: 2 / factor) { i in
            CGFloat(ObsidianGraphSettings.nodeSize(weight: weights[ids[i]] ?? 0, multiplier: multiplier)) / root
        }
    }

    /// The notes that stay lit: the hovered note and its neighbors, else an account's notes, else the selected note's.
    public var focus: Set<String>? {
        if let id = hovered { return neighbors(of: id).union([id]) }
        if let slug = highlightedAccount { return notes(savedBy: slug) }
        if let id = selected { return neighbors(of: id).union([id]) }
        return nil
    }

    /// The note the focus is on: in a vault, the lines that touch it light up.
    public var focusCenter: String? { hovered ?? (highlightedAccount == nil ? selected : nil) }

    /// How visible a node is now: from 0.2 to 1 in a vault, from 0.28 to 1 in a memory.
    public func fade(_ id: String) -> Double { fades[id] ?? 1 }

    /// A memory fades a quarter of the way each frame (about 180 ms to 95%); a vault keeps Obsidian's tenth.
    private var fadeRate: Double { style == .vault ? 0.1 : 0.25 }
    private var dimmedAlpha: Double { style == .vault ? Self.fadedAlpha : Self.memoryDimmed }
    private var threadsDimmed: Double { style == .vault ? Self.fadedAlpha : Self.memoryThreadsDimmed }

    private func focusChanged() {
        if let focus { lastFocus = focus }
        fading = true
        if reduceMotion { stepFades() }
        animate()
    }

    /// Obsidian's soft fade: every frame each node moves part of the way toward its target. At once with Reduce Motion.
    private func stepFades() {
        guard fading else { return }
        let focus = self.focus, rate = fadeRate, dimmed = dimmedAlpha
        func toward(_ value: Double, _ target: Double) -> Double {
            if reduceMotion { return target }
            let next = value * (1 - rate) + target * rate
            return abs(next - target) < 0.005 ? target : next
        }
        var moving = false
        for node in graph.nodes {
            let target = focus.map { $0.contains(node.id) ? 1 : dimmed } ?? 1
            let value = toward(fades[node.id] ?? 1, target)
            fades[node.id] = value == 1 ? nil : value
            if value != target { moving = true }
        }
        let lineTarget = focus == nil ? 1 : threadsDimmed
        lineFade = toward(lineFade, lineTarget)
        fading = moving || lineFade != lineTarget
    }

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
        } else if style == .vault {
            // A link to nothing has no file, and a vault has no hubs.
            return nil
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
        // Notes only: a vault's canvases, bases and attachments are not text to preview.
        guard let file = graph.node(id)?.file, file.lowercased().hasSuffix(".md"), let url = fileURL(id) else { return "" }
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

    public var isMoving: Bool {
        (!layout.isSettled && !quiet && !awaitingFirstLayout) || !pulses.isEmpty || dragged != nil || fading || bloom != nil || cameraTween != nil
    }

    public func position(of id: String) -> CGPoint? { layout.position(of: id) }

    public func drag(_ id: String, to point: CGPoint) { dragged = id; bloom = nil; layout.drag(id, to: point); layoutGeneration += 1; animate() }
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
        guard quiet, settleTask == nil, dragged == nil, layout.count > 0, !layout.isSettled else { return }
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
            if !self.fitted, self.viewSize != .zero {
                self.camera.fit(settled.bounds, in: self.viewSize, top: self.chrome.top, bottom: self.chrome.bottom); self.fitted = true
            }
            if self.awaitingFirstLayout { self.awaitingFirstLayout = false; self.revealedAt = self.clock() }
            self.frame &+= 1
        }
    }

    /// Frames the whole graph, gliding there.
    public func fitNow() {
        guard layout.count > 0, viewSize != .zero else { return }
        var target = camera
        target.fit(layout.bounds, in: viewSize, top: chrome.top, bottom: chrome.bottom)
        glide(to: target, kind: .fit)
    }

    /// The zoom buttons: about the view's center, gliding; a second click goes on from where the first one was going.
    public func zoom(by factor: CGFloat) {
        fitted = true
        var target = cameraTween?.to ?? camera
        target.zoom(by: factor, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), in: viewSize)
        glide(to: target, kind: .zoom)
    }

    private func glide(to target: GraphCamera, kind: CameraTween.Kind) {
        guard !reduceMotion else { camera = target; cameraTween = nil; tweenCamera = nil; return }
        cameraTween = CameraTween(from: camera, to: target, kind: kind, start: clock())
        tweenCamera = camera
        animate()
    }

    func tick() {
        let now = clock()
        if let bloom, (Beat.elapsed(since: bloom.start, at: now) ?? 0) >= bloom.duration { self.bloom = nil }
        // While the first layout settles out of sight, or blooms, the layout holds still.
        if dragged != nil || (!quiet && !awaitingFirstLayout && bloom == nil && !layout.isSettled) { layout.step() }
        // A graph that was empty at first unfolds live: until the person moves around, the camera follows it.
        if !fitted, !quiet, !awaitingFirstLayout, layout.count > 0, viewSize != .zero {
            camera.fit(layout.bounds, in: viewSize, top: chrome.top, bottom: chrome.bottom)
            if layout.isSettled { fitted = true }
        }
        // A glide goes on only while nothing else moved the camera.
        if let tween = cameraTween {
            if camera != tweenCamera {
                cameraTween = nil; tweenCamera = nil
            } else {
                camera = tween.camera(at: now); tweenCamera = camera
                if tween.isOver(at: now) { cameraTween = nil; tweenCamera = nil }
            }
        }
        if !pulses.isEmpty { pulses = pulses.filter { now.timeIntervalSince($0.value.start) < Self.pulseDuration * Theme.Motion.slow } }
        stepFades()
        frame &+= 1
        if !isMoving { timer?.invalidate(); timer = nil }
    }

    /// Stops the animation (the screen went away). It starts again with the next change.
    public func stop() { timer?.invalidate(); timer = nil }
}

/// What a vault's read brings back from off the main thread.
struct VaultRead: Sendable {
    let stamp: String
    let settings: ObsidianGraphSettings
    let shown: ObsidianGraphFilter.Shown
}
