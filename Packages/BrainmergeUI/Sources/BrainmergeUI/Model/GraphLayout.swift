import BrainmergeCore
import CoreGraphics
import Foundation

/// The forces of a layout. Brainmerge's own keep a memory compact; an Obsidian vault gets Obsidian's, from its sliders.
struct GraphForces: Equatable, Sendable {
    /// The pull of every note toward the center.
    var center: Double
    /// How hard notes push each other away (negative).
    var charge: Double
    /// Beyond this distance notes stop pushing; nil for no limit, as in Obsidian.
    var chargeReach: Double?
    /// The rest length of a link, and how hard it pulls (divided by the fewer links of its two ends).
    var linkDistance: Double
    var linkStrength: Double
    /// Notes closer than twice this radius are pushed apart; 0 for none.
    var collideRadius: Double
    var collideStrength: Double
    /// How warm a change of the graph makes the simulation again.
    var reheat: Double

    static let brainmerge = GraphForces(center: 0.035, charge: -140, chargeReach: 900, linkDistance: 46, linkStrength: 1,
                                        collideRadius: 0, collideStrength: 0, reheat: 0.35)

    /// Obsidian's simulation, measured in its code: the four sliders converted as its force panel converts them, no
    /// cutoff to the repulsion, a collision radius of 60 at half strength, a reheat of 0.3.
    static func obsidian(_ settings: ObsidianGraphSettings) -> GraphForces {
        GraphForces(center: settings.centerForce, charge: -settings.repelForce, chargeReach: nil, linkDistance: settings.linkDistance,
                    linkStrength: settings.linkForce, collideRadius: 60, collideStrength: 0.5, reheat: 0.3)
    }
}

/// A force-directed layout, the same family of physics as Obsidian's graph view (and d3's force simulation):
/// every note repels the others, links pull their two notes together like springs, a light gravity keeps the
/// graph centered, and the whole thing cools down until it stops moving.
///
/// Plain value type, deterministic (same graph, same picture), cheap to step: repulsion only looks at notes in
/// neighboring cells of a grid, so a vault of a few thousand notes still steps well within a frame.
struct GraphLayout: Sendable {
    private(set) var ids: [String] = []
    private var index: [String: Int] = [:]
    private var x: [Double] = [], y: [Double] = [], vx: [Double] = [], vy: [Double] = []
    private var pinned: [String: CGPoint] = [:]
    private var links: [(Int, Int)] = []
    private(set) var degree: [Int] = []

    private(set) var alpha: Double = 1
    private var alphaTarget: Double = 0
    static let alphaMin = 0.001
    static let alphaDecay = 1 - pow(0.001, 1.0 / 300)
    static let velocityDecay = 0.4
    static let theta = 0.9
    private(set) var forces: GraphForces

    init(forces: GraphForces = .brainmerge) { self.forces = forces }

    /// New forces (a vault's settings changed) wake the simulation; the same ones leave it at rest.
    mutating func setForces(_ new: GraphForces) {
        guard new != forces else { return }
        forces = new
        reheat(new.reheat)
    }

    var isSettled: Bool { alpha < Self.alphaMin && alphaTarget == 0 }
    var count: Int { ids.count }
    var maxSpeed: Double { zip(vx, vy).map { hypot($0, $1) }.max() ?? 0 }

    func position(of id: String) -> CGPoint? { index[id].map { CGPoint(x: x[$0], y: y[$0]) } }
    func position(at i: Int) -> CGPoint { CGPoint(x: x[i], y: y[i]) }
    func indexOf(_ id: String) -> Int? { index[id] }
    var linkIndices: [(Int, Int)] { links }

    /// Brings the layout in line with the graph: existing notes keep their place, new notes appear next to a note
    /// they link to (or on a spiral around the center), removed notes go. Any change wakes the simulation up.
    /// Each pair is a spring: a vault passes a link written both ways twice, as Obsidian does.
    mutating func sync(nodes: [String], edges: [(String, String)]) {
        let old = index
        let oldX = x, oldY = y, oldVX = vx, oldVY = vy
        var newIndex: [String: Int] = [:]
        for (i, id) in nodes.enumerated() { newIndex[id] = i }
        var nx = [Double](repeating: 0, count: nodes.count), ny = nx, nvx = nx, nvy = nx
        var placed = [Bool](repeating: false, count: nodes.count)
        for (i, id) in nodes.enumerated() {
            if let j = old[id] { nx[i] = oldX[j]; ny[i] = oldY[j]; nvx[i] = oldVX[j]; nvy[i] = oldVY[j]; placed[i] = true }
        }
        let newLinks = edges.compactMap { e -> (Int, Int)? in
            guard let a = newIndex[e.0], let b = newIndex[e.1], a != b else { return nil }
            return (a, b)
        }
        var neighbors = [[Int]](repeating: [], count: nodes.count)
        for (a, b) in newLinks { neighbors[a].append(b); neighbors[b].append(a) }
        let wasEmpty = old.isEmpty
        // Compared as sets of named pairs: a link rewired from one note to another counts, even at the same count.
        func pairs(_ links: [(Int, Int)], _ names: [String]) -> Set<String> {
            Set(links.map { let a = names[$0.0], b = names[$0.1]; return a < b ? a + "\u{0}" + b : b + "\u{0}" + a })
        }
        var changed = nodes.count != ids.count || newLinks.count != links.count || pairs(newLinks, nodes) != pairs(links, ids)
        // Placement scales with the rest length, so longer links do not start from a knot that bursts open.
        let spread = forces.linkDistance / GraphForces.brainmerge.linkDistance
        for (i, id) in nodes.enumerated() where !placed[i] {
            changed = true
            let seed = Self.hash(id)
            let angle = Double(seed % 6283) / 1000
            if !wasEmpty, let anchor = neighbors[i].first(where: { placed[$0] }) {
                let r = (18 + Double(seed % 17)) * spread
                nx[i] = nx[anchor] + cos(angle) * r; ny[i] = ny[anchor] + sin(angle) * r
            } else {
                // A phyllotaxis spiral, like d3's initial placement: even, deterministic, no overlap.
                let k = Double(i)
                let radius = 12 * spread * sqrt(0.5 + k), theta = k * Double.pi * (3 - sqrt(5))
                nx[i] = radius * cos(theta); ny[i] = radius * sin(theta)
            }
            placed[i] = true
        }
        ids = nodes; index = newIndex; x = nx; y = ny; vx = nvx; vy = nvy; links = newLinks
        degree = neighbors.map(\.count)
        pinned = pinned.filter { newIndex[$0.key] != nil }
        if changed { alpha = max(alpha, wasEmpty ? 1 : forces.reheat) }
    }

    /// One tick of the simulation.
    mutating func step() {
        let n = ids.count
        guard n > 0 else { return }
        alpha += (alphaTarget - alpha) * Self.alphaDecay
        // Links: springs toward a rest length, weaker on well-connected notes (so hubs do not collapse).
        for (s, t) in links {
            var dx = x[t] + vx[t] - x[s] - vx[s], dy = y[t] + vy[t] - y[s] - vy[s]
            if dx == 0 && dy == 0 { dx = 0.01; dy = 0.01 }
            let l = (dx * dx + dy * dy).squareRoot()
            let ds = Double(degree[s]), dt = Double(degree[t])
            let strength = forces.linkStrength / max(1, min(ds, dt))
            let k = (l - forces.linkDistance) / l * alpha * strength
            let bias = ds / max(1, ds + dt)
            vx[t] -= dx * k * bias; vy[t] -= dy * k * bias
            vx[s] += dx * k * (1 - bias); vy[s] += dy * k * (1 - bias)
        }
        // Repulsion: every note pushes the others away. Far groups of notes act as one body (Barnes-Hut),
        // so a step costs about n log n instead of n squared.
        let tree = QuadTree(x: x, y: y)
        let theta2 = Self.theta * Self.theta, reach2 = forces.chargeReach.map { $0 * $0 } ?? .infinity
        let chargeAlpha = forces.charge * alpha
        x.withUnsafeBufferPointer { px in y.withUnsafeBufferPointer { py in
        vx.withUnsafeMutableBufferPointer { pvx in vy.withUnsafeMutableBufferPointer { pvy in
        tree.nodes.withUnsafeBufferPointer { nodes in tree.next.withUnsafeBufferPointer { next in
            var stack = [Int32](); stack.reserveCapacity(64)
            for i in 0..<n {
                let xi = px[i], yi = py[i]
                var fx = 0.0, fy = 0.0
                stack.removeAll(keepingCapacity: true); stack.append(0)
                while let top = stack.popLast() {
                    let node = nodes[Int(top)]
                    if node.count == 0 { continue }
                    let dx = node.cx - xi, dy = node.cy - yi
                    let l = dx * dx + dy * dy
                    if node.child < 0 {
                        var j = node.head
                        while j >= 0 {
                            let jj = Int(j)
                            if jj != i {
                                var ex = px[jj] - xi, ey = py[jj] - yi
                                var el = ex * ex + ey * ey
                                if el < reach2 {
                                    if el < 1 { ex = Double((i * 7 + jj * 13) % 5) - 1.5; ey = Double((i * 3 + jj * 11) % 5) - 1.5; el = ex * ex + ey * ey }
                                    let w = chargeAlpha / el
                                    fx += ex * w; fy += ey * w
                                }
                            }
                            j = next[jj]
                        }
                    } else if node.size * node.size < theta2 * l {
                        if l < reach2 { let w = chargeAlpha * Double(node.count) / l; fx += dx * w; fy += dy * w }
                    } else {
                        for c in 0..<4 { stack.append(node.child + Int32(c)) }
                    }
                }
                pvx[i] += fx; pvy[i] += fy
            }
        } }
        } }
        } }
        if forces.collideRadius > 0 { collide() }
        // Gravity toward the center, then integration with friction.
        var held: [Int: CGPoint] = [:]
        for (id, point) in pinned { if let i = index[id] { held[i] = point } }
        let gravity = forces.center
        for i in 0..<n {
            vx[i] -= x[i] * gravity * alpha; vy[i] -= y[i] * gravity * alpha
            if let p = held[i] { x[i] = p.x; y[i] = p.y; vx[i] = 0; vy[i] = 0; continue }
            vx[i] *= 1 - Self.velocityDecay; vy[i] *= 1 - Self.velocityDecay
            x[i] += vx[i]; y[i] += vy[i]
        }
    }

    /// d3's collision force, as Obsidian uses it: two notes whose next positions are closer than two radii are pushed
    /// apart, each half the way, whatever the temperature. Neighbors are found in a grid of cells two radii wide, so
    /// only the nine cells around a note are looked at.
    private mutating func collide() {
        let n = ids.count
        let reach = forces.collideRadius * 2, reach2 = reach * reach, strength = forces.collideStrength
        func key(_ cx: Int, _ cy: Int) -> Int64 { Int64(cx) << 32 | Int64(UInt32(truncatingIfNeeded: cy)) }
        var cells: [Int64: [Int32]] = [:]
        cells.reserveCapacity(n)
        var cellX = [Int](repeating: 0, count: n), cellY = cellX
        for i in 0..<n {
            let px = x[i] + vx[i], py = y[i] + vy[i]
            guard px.isFinite, py.isFinite else { continue }
            cellX[i] = Int((px / reach).rounded(.down)); cellY[i] = Int((py / reach).rounded(.down))
            cells[key(cellX[i], cellY[i]), default: []].append(Int32(i))
        }
        for i in 0..<n {
            let xi = x[i] + vx[i], yi = y[i] + vy[i]
            guard xi.isFinite, yi.isFinite else { continue }
            for dx in -1...1 { for dy in -1...1 {
                guard let bucket = cells[key(cellX[i] + dx, cellY[i] + dy)] else { continue }
                for j32 in bucket {
                    let j = Int(j32)
                    guard j > i else { continue }
                    var ex = xi - x[j] - vx[j], ey = yi - y[j] - vy[j]
                    var l = ex * ex + ey * ey
                    guard l < reach2 else { continue }
                    // Two notes on the very same spot: a small, stable nudge instead of d3's random one.
                    if ex == 0 { ex = Double((i * 7 + j * 13) % 5 + 1) * 1e-6; l += ex * ex }
                    if ey == 0 { ey = Double((i * 3 + j * 11) % 5 + 1) * 1e-6; l += ey * ey }
                    l = l.squareRoot()
                    let k = (reach - l) / l * strength
                    ex *= k; ey *= k
                    vx[i] += ex * 0.5; vy[i] += ey * 0.5
                    vx[j] -= ex * 0.5; vy[j] -= ey * 0.5
                }
            } }
        }
    }

    /// Dragging holds a note under the pointer and keeps the rest of the graph warm, like Obsidian.
    mutating func drag(_ id: String, to point: CGPoint) {
        guard let i = index[id] else { return }
        pinned[id] = point; x[i] = point.x; y[i] = point.y
        alphaTarget = 0.3
        alpha = max(alpha, 0.3)
    }

    mutating func release(_ id: String) {
        pinned[id] = nil
        alphaTarget = 0
    }

    mutating func reheat(_ value: Double = 0.3) { alpha = max(alpha, value) }

    /// The note under a point, in layout units: each note reaches `limit` from its center, or its radius plus `margin`
    /// when larger. Among those in reach, the one whose edge is nearest wins, so a pointer on a large note picks it
    /// over a small one's nearby center. Without radii, the note whose center is closest.
    func nearest(to point: CGPoint, within limit: CGFloat, margin: CGFloat = 0, radius: (Int) -> CGFloat = { _ in 0 }) -> String? {
        var best: (Int, Double)?
        for i in 0..<ids.count {
            let d = hypot(x[i] - point.x, y[i] - point.y), r = radius(i)
            guard d <= max(limit, r + margin) else { continue }
            if d - r < (best?.1 ?? .infinity) { best = (i, d - r) }
        }
        return best.map { ids[$0.0] }
    }

    /// The rectangle holding every note.
    var bounds: CGRect {
        guard let minX = x.min(), let maxX = x.max(), let minY = y.min(), let maxY = y.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// FNV-1a: a stable hash (Swift's own hash changes at every launch).
    static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return h
    }
}

/// A quadtree over the notes' positions, for Barnes-Hut: each cell knows how many notes it holds and their center.
/// Leaves chain their notes through `next`, so notes at the very same place never force endless subdivision.
struct QuadTree {
    struct Node { var x0: Double; var y0: Double; var size: Double; var cx: Double; var cy: Double; var count: Int; var child: Int32; var head: Int32 }
    private(set) var nodes: [Node] = []
    private(set) var next: [Int32]

    init(x: [Double], y: [Double]) {
        let n = x.count
        next = [Int32](repeating: -1, count: n)
        guard n > 0, let minX = x.min(), let maxX = x.max(), let minY = y.min(), let maxY = y.max() else {
            nodes = [Node(x0: 0, y0: 0, size: 1, cx: 0, cy: 0, count: 0, child: -1, head: -1)]; return
        }
        let size = max(maxX - minX, maxY - minY, 1) * 1.0001
        nodes.reserveCapacity(n * 2)
        nodes.append(Node(x0: minX, y0: minY, size: size, cx: 0, cy: 0, count: 0, child: -1, head: -1))
        for i in 0..<n { insert(i, x[i], y[i], x, y) }
        finish(0)
    }

    private mutating func insert(_ i: Int, _ px: Double, _ py: Double, _ x: [Double], _ y: [Double]) {
        var at = 0
        while true {
            nodes[at].cx += px; nodes[at].cy += py; nodes[at].count += 1
            if nodes[at].child >= 0 { at = Int(nodes[at].child) + quadrant(at, px, py); continue }
            if nodes[at].head < 0 || nodes[at].size < 0.5 { next[i] = nodes[at].head; nodes[at].head = Int32(i); return }
            // Split the leaf: move the notes it held down one level, then keep inserting.
            let half = nodes[at].size / 2, x0 = nodes[at].x0, y0 = nodes[at].y0
            let first = Int32(nodes.count)
            for q in 0..<4 {
                nodes.append(Node(x0: x0 + (q & 1 == 1 ? half : 0), y0: y0 + (q & 2 == 2 ? half : 0), size: half, cx: 0, cy: 0, count: 0, child: -1, head: -1))
            }
            var j = nodes[at].head
            nodes[at].child = first; nodes[at].head = -1
            while j >= 0 {
                let jj = Int(j), following = next[jj]
                let c = Int(first) + quadrant(at, x[jj], y[jj])
                nodes[c].cx += x[jj]; nodes[c].cy += y[jj]; nodes[c].count += 1
                next[jj] = nodes[c].head; nodes[c].head = j
                j = following
            }
            at = Int(first) + quadrant(at, px, py)
        }
    }

    private func quadrant(_ at: Int, _ px: Double, _ py: Double) -> Int {
        let half = nodes[at].size / 2
        return (px >= nodes[at].x0 + half ? 1 : 0) | (py >= nodes[at].y0 + half ? 2 : 0)
    }

    /// Sums become centers of mass.
    private mutating func finish(_ at: Int) {
        if nodes[at].count > 0 { nodes[at].cx /= Double(nodes[at].count); nodes[at].cy /= Double(nodes[at].count) }
        if nodes[at].child >= 0 { for c in 0..<4 { finish(Int(nodes[at].child) + c) } }
    }
}

