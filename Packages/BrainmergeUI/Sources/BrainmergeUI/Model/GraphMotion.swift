import CoreGraphics
import Foundation

/// The zoom buttons and Fit glide instead of jumping: zoom 0.2 s on the ease-out, the scale geometric (every step of the
/// way looks like the same zoom); Fit 0.35 s on the in-out curve, on the center and the logarithm of the scale. Pure: the
/// model applies it on each frame, and any gesture that moves the camera meanwhile cancels it.
struct CameraTween: Equatable {
    enum Kind: Equatable { case zoom, fit }
    let from: GraphCamera
    let to: GraphCamera
    let kind: Kind
    let start: Date

    var duration: Double { kind == .zoom ? 0.2 : 0.35 }

    func progress(at date: Date) -> Double {
        let t = Ease.progress((Beat.elapsed(since: start, at: date) ?? 0), from: 0, over: duration)
        return kind == .zoom ? Ease.out(t) : Ease.inOut(t)
    }

    func isOver(at date: Date) -> Bool { (Beat.elapsed(since: start, at: date) ?? 0) >= duration }

    func camera(at date: Date) -> GraphCamera {
        if isOver(at: date) { return to }
        let e = progress(at: date)
        var camera = from
        camera.scale = CGFloat(exp(Ease.lerp(log(Double(from.scale)), log(Double(to.scale)), e)))
        if kind == .fit { camera.center = Ease.lerp(from.center, to.center, e) }
        if e == 0 { return from }
        return camera
    }
}

/// The first read of a memory blooms: once its layout has settled out of sight and the camera framed it, each note
/// travels out from its project's hub to its place in 0.65 s on the ease-out, 30 ms later per link away from the hub
/// (240 ms at most), fading in over its first 0.2 s. A thread draws once both its ends are past 60% of their way. A note
/// no hub reaches fades in where it is.
struct GraphBloom {
    static let travel = 0.65
    static let perHop = 0.03
    static let maxDelay = 0.24
    static let fade = 0.2
    static let threadFrom = 0.6

    let start: Date
    /// Where each note starts: its hub's place, or its own.
    let origins: [CGPoint]
    let delays: [Double]
    let duration: Double

    init(ids: [String], links: [(Int, Int)], positions: [CGPoint], start: Date) {
        self.start = start
        var neighbors = [[Int]](repeating: [], count: ids.count)
        for (a, b) in links where a < ids.count && b < ids.count { neighbors[a].append(b); neighbors[b].append(a) }
        // A breadth-first walk from every hub at once: each note gets the nearest hub and how many links away it is.
        var hub = [Int?](repeating: nil, count: ids.count), hops = [Int](repeating: 0, count: ids.count)
        var queue = ids.indices.filter { ids[$0].hasPrefix("project:") }
        for i in queue { hub[i] = i }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            for j in neighbors[i] where hub[j] == nil {
                hub[j] = hub[i]; hops[j] = hops[i] + 1; queue.append(j)
            }
        }
        origins = ids.indices.map { hub[$0].map { positions[$0] } ?? positions[$0] }
        delays = hops.map { min(Double($0) * Self.perHop, Self.maxDelay) }
        duration = (delays.max() ?? 0) + Self.travel
    }

    /// How far along its way a note is, eased.
    func travel(_ i: Int, elapsed: Double) -> Double { Ease.out(Ease.progress(elapsed, from: delays[i], over: Self.travel)) }

    func position(_ i: Int, target: CGPoint, elapsed: Double) -> CGPoint {
        if elapsed >= duration { return target }
        let e = travel(i, elapsed: elapsed)
        if e == 0 { return origins[i] }
        return Ease.lerp(origins[i], target, e)
    }

    func opacity(_ i: Int, elapsed: Double) -> Double { Ease.out(Ease.progress(elapsed, from: delays[i], over: Self.fade)) }

    func edgeOpacity(_ a: Int, _ b: Int, elapsed: Double) -> Double {
        let both = min(travel(a, elapsed: elapsed), travel(b, elapsed: elapsed))
        return Ease.clamp01((both - Self.threadFrom) / (1 - Self.threadFrom))
    }
}

/// A note written or saved: a ring from r+3 to r+20 over 1.2 s (radius eased out cubic, opacity 0.8 (1 - t) squared,
/// 1.5 pt), a second ring 0.18 s later and a pop of the bubble when an account saved it, and a halo that stays 2.6 s so
/// the note is easy to find. With Reduce Motion, the halo only.
enum GraphPulse {
    static let ring = Theme.Motion.ring
    static let second = 0.18
    static let from: CGFloat = 3, to: CGFloat = 20
    static let peak = 0.8
    static let lineWidth: CGFloat = 1.5
    static let haloPeak = 0.35
    static let halo: TimeInterval = 2.6
    /// The pop of a saved bubble: its radius times (1 + 0.25 bump); up in 90 ms, then it settles like a hop.
    static let pop = 0.25
    static let rise = 0.09
    static let settle = Ease.Spring(response: 0.28, damping: 0.55)

    struct Ring: Equatable { var offset: CGFloat; var opacity: Double }

    static func rings(elapsed: Double, saved: Bool) -> [Ring] {
        (saved ? [0, second] : [0]).compactMap { delay in
            let t = (elapsed - delay) / ring
            guard t >= 0, t < 1 else { return nil }
            return Ring(offset: from + (to - from) * CGFloat(1 - pow(1 - t, 3)), opacity: peak * (1 - t) * (1 - t))
        }
    }

    static func bump(elapsed: Double) -> Double {
        if elapsed <= 0 { return 0 }
        if elapsed < rise { return Ease.out(elapsed / rise) }
        return 1 - settle.value(elapsed - rise)
    }

    static func haloOpacity(elapsed: Double) -> Double {
        let t = Ease.clamp01(elapsed / halo)
        return haloPeak * pow(1 - t, 1.5)
    }
}
