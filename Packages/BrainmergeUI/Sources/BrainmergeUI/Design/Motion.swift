import CoreGraphics
import Foundation

/// The one easing library of the app: every scene (the creature's life, the launch, How it works) is a pure function
/// of time built from these. Same input, same output: frames are deterministic and testable.
public enum Ease {
    /// A CSS-style cubic-bezier(x1, y1, x2, y2), solved for x with Newton's method, then bisection (the WebKit approach).
    public struct Bezier: Sendable, Equatable {
        public let x1: Double, y1: Double, x2: Double, y2: Double
        public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

        private func sample(_ a1: Double, _ a2: Double, _ s: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a1 + 3 * u * s * s * a2 + s * s * s
        }
        private func slope(_ s: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2)
        }
        public func callAsFunction(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            var s = x
            for _ in 0..<8 {
                let error = sample(x1, x2, s) - x
                if abs(error) < 1e-7 { return sample(y1, y2, s) }
                let d = slope(s)
                if abs(d) < 1e-6 { break }
                s = min(1, max(0, s - error / d))
            }
            var lo = 0.0, hi = 1.0
            s = x
            for _ in 0..<50 {
                let v = sample(x1, x2, s)
                if abs(v - x) < 1e-9 { break }
                if v < x { lo = s } else { hi = s }
                s = (lo + hi) / 2
            }
            return sample(y1, y2, s)
        }
    }

    /// Entering, exiting, feedback: cubic-bezier(0.23, 1, 0.32, 1) (Theme.Motion.out, the site's --ease-out).
    public static let out = Bezier(0.23, 1, 0.32, 1)
    /// Moving on screen: cubic-bezier(0.77, 0, 0.175, 1) (Theme.Motion.inOut, the site's --ease-move).
    public static let inOut = Bezier(0.77, 0, 0.175, 1)
    /// A throw that leaves quickly and lands gently: cubic-bezier(0.45, 0, 0.2, 1).
    public static let glide = Bezier(0.45, 0, 0.2, 1)
    /// Plain ease, for color crossfades: cubic-bezier(0.25, 0.1, 0.25, 1).
    public static let ease = Bezier(0.25, 0.1, 0.25, 1)
    /// A gentle, sine-like in-out for breathing: cubic-bezier(0.45, 0, 0.55, 1).
    public static let breath = Bezier(0.45, 0, 0.55, 1)
    /// A size change in flight: cubic-bezier(0.45, 0, 0.25, 1).
    public static let shrink = Bezier(0.45, 0, 0.25, 1)
    /// The horizontal travel of a leap, nearly constant like a thrown body, softened at the end: cubic-bezier(0.33, 0.33, 0.55, 1).
    public static let travel = Bezier(0.33, 0.33, 0.55, 1)

    public static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    public static func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
    public static func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
    }
    /// 0 before `start`, 1 after `start + duration`, linear in between.
    public static func progress(_ t: Double, from start: Double, over duration: Double) -> Double {
        duration <= 0 ? (t >= start ? 1 : 0) : clamp01((t - start) / duration)
    }
    /// Stepped values for pixel art: the value of the last key whose time is at or before `t`, else `before`.
    public static func steps(_ t: Double, _ keys: [(Double, Double)], before: Double) -> Double {
        var value = before
        for (time, v) in keys where t >= time { value = v }
        return value
    }

    /// A damped spring in SwiftUI's terms (`.spring(response:dampingFraction:)`), in closed form: omega0 = 2 pi / response.
    public struct Spring: Sendable, Equatable {
        public var response: Double
        public var damping: Double
        public init(response: Double, damping: Double) { self.response = response; self.damping = damping }

        /// The distance from the target `t` seconds after release, from a displacement `x0` and a velocity `v0` (per second).
        public func displacement(_ t: Double, from x0: Double, velocity v0: Double = 0) -> Double {
            guard t > 0 else { return x0 }
            let w = 2 * Double.pi / response, z = damping
            if z < 1 {
                let wd = w * (1 - z * z).squareRoot()
                return exp(-z * w * t) * (x0 * cos(wd * t) + (v0 + z * w * x0) / wd * sin(wd * t))
            }
            return (x0 + (v0 + w * x0) * t) * exp(-w * t)
        }
        /// 0 to 1, starting at rest.
        public func value(_ t: Double) -> Double { 1 + displacement(t, from: -1) }
    }

    /// A spring's step response from 0 to 1, `t` seconds after it started (0 before).
    public static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        Spring(response: response, damping: damping).value(t)
    }
    /// 1 at the start, ringing down to 0 like a released spring: the settle after a squash.
    public static func ringDown(_ t: Double, response: Double, damping: Double) -> Double {
        1 - spring(t, response: response, damping: damping)
    }
    /// A spring kicked from rest: 0 at the start, a peak normalized to 1, a small rebound, back to 0.
    public static func impulse(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let w0 = 2 * Double.pi / response
        let z = min(damping, 0.999)
        let wd = w0 * (1 - z * z).squareRoot()
        let peakTime = atan(wd / (z * w0)) / wd
        let peak = exp(-z * w0 * peakTime) * sin(wd * peakTime)
        return exp(-z * w0 * t) * sin(wd * t) / peak
    }
    /// Rises over `rise` seconds from `start`, holds, then falls over `fall` seconds ending at `end`; 0 outside.
    public static func envelope(_ t: Double, start: Double, rise: Double, end: Double, fall: Double,
                                up: Bezier = Ease.out, down: Bezier = Ease.ease) -> Double {
        if t < start || t > end { return 0 }
        let a = up(progress(t, from: start, over: rise))
        let b = 1 - down(progress(t, from: end - fall, over: fall))
        return min(a, b)
    }
}

/// A cubic Bezier path, reparametrized by arc length so a point travels it at an even speed.
public struct ArcPath: Sendable {
    public let p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint
    public let length: Double
    private let table: [Double]   // cumulative length at each sample
    static let samples = 64

    public init(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0; self.p1 = p1; self.p2 = p2; self.p3 = p3
        var lengths = [0.0], previous = p0
        for i in 1...Self.samples {
            let q = Self.raw(p0, p1, p2, p3, Double(i) / Double(Self.samples))
            lengths.append(lengths[i - 1] + hypot(q.x - previous.x, q.y - previous.y))
            previous = q
        }
        table = lengths
        length = lengths.last ?? 0
    }

    static func raw(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                       y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
    }

    /// The curve parameter at a fraction `s` (0...1) of the length.
    public func parameter(atFraction s: Double) -> Double {
        let target = Ease.clamp01(s) * length
        var lo = 0, hi = Self.samples
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if table[mid] < target { lo = mid } else { hi = mid }
        }
        let span = table[hi] - table[lo]
        let f = span > 0 ? (target - table[lo]) / span : 0
        return (Double(lo) + f) / Double(Self.samples)
    }

    public func point(atFraction s: Double) -> CGPoint { Self.raw(p0, p1, p2, p3, parameter(atFraction: s)) }

    /// The unit tangent at a fraction of the length.
    public func tangent(atFraction s: Double) -> CGVector {
        let t = parameter(atFraction: s), u = 1 - t
        let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
        let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
        let n = max(hypot(dx, dy), 1e-6)
        return CGVector(dx: dx / n, dy: dy / n)
    }

    /// The piece of the curve between two fractions of its length, as a polyline (trails that draw themselves).
    public func segment(from a: Double, to b: Double, steps: Int = 40) -> [CGPoint] {
        let a = Ease.clamp01(a), b = Ease.clamp01(b)
        guard b > a, steps > 0 else { return [] }
        return (0...steps).map { point(atFraction: a + (b - a) * Double($0) / Double(steps)) }
    }
}

/// The only randomness of the scenes: fixed seeds, so an irregular rhythm is identical on every run.
public enum Dice {
    /// SplitMix64 of a seed, an index and a stream, as a number in 0..<1.
    public static func unit(_ seed: UInt64, _ index: UInt64, _ stream: UInt64) -> Double {
        var z = seed &+ index &* 0x9E3779B97F4A7C15 &+ stream &* 0xD1B54A32D192ED03
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
    /// A hash of two grid coordinates and a salt in 0..<1: the same pixel always gets the same path.
    public static func hash01(_ x: Int, _ y: Int, _ salt: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 73_856_093 ^ y &* 19_349_663 ^ salt &* 83_492_791))
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33; h &*= 0xc4ceb9fe1a85ec53; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
