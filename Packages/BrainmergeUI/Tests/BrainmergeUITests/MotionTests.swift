import CoreGraphics
import Foundation
import Testing
@testable import BrainmergeUI

/// The one easing library every scene uses: pure functions of a progress or a time.
@Suite struct MotionTests {
    static let curves: [(String, Ease.Bezier)] = [
        ("out", Ease.out), ("inOut", Ease.inOut), ("glide", Ease.glide), ("ease", Ease.ease),
        ("breath", Ease.breath), ("shrink", Ease.shrink), ("travel", Ease.travel),
    ]

    @Test func everyCurveRunsFromZeroToOneWithoutGoingBack() {
        for (name, curve) in Self.curves {
            #expect(abs(curve(0)) < 1e-9, "\(name) at 0")
            #expect(abs(curve(1) - 1) < 1e-9, "\(name) at 1")
            var last = -1.0
            for i in 0...1000 {
                let v = curve(Double(i) / 1000)
                #expect(v >= last - 1e-9, "\(name) goes back at \(i)")
                last = v
            }
            // Outside 0...1 the curve holds its ends.
            #expect(abs(curve(-0.5)) < 1e-9 && abs(curve(1.5) - 1) < 1e-9, "\(name) clamps")
        }
    }

    @Test func theCurvesAreTheOnesTheSiteUses() {
        // cubic-bezier(0.23, 1, 0.32, 1) rises fast: past 80% at a third of the way.
        #expect(Ease.out(1.0 / 3) > 0.8)
        // The in-out leaves and arrives slowly: under 5% at a tenth, over 95% at nine tenths.
        #expect(Ease.inOut(0.1) < 0.05 && Ease.inOut(0.9) > 0.95)
        // The breath is symmetric around the middle.
        #expect(abs(Ease.breath(0.5) - 0.5) < 1e-3)
        #expect(abs(Ease.breath(0.2) + Ease.breath(0.8) - 1) < 1e-3)
    }

    @Test func progressLerpClampAndSteps() {
        #expect(Ease.progress(0.5, from: 0, over: 1) == 0.5)
        #expect(Ease.progress(-1, from: 0, over: 1) == 0 && Ease.progress(3, from: 0, over: 1) == 1)
        #expect(Ease.progress(2, from: 2, over: 0) == 1 && Ease.progress(1.9, from: 2, over: 0) == 0)
        #expect(Ease.lerp(2, 4, 0.25) == 2.5)
        #expect(Ease.clamp01(-0.1) == 0 && Ease.clamp01(1.2) == 1 && Ease.clamp01(0.3) == 0.3)
        let keys: [(Double, Double)] = [(0.1, 1), (0.2, 2), (0.3, 3)]
        #expect(Ease.steps(0.05, keys, before: 0) == 0)
        #expect(Ease.steps(0.1, keys, before: 0) == 1)
        #expect(Ease.steps(0.25, keys, before: 0) == 2)
        #expect(Ease.steps(9, keys, before: 0) == 3)
    }

    @Test func aSpringSettlesWithinThreeResponses() {
        for (response, damping) in [(0.30, 0.86), (0.34, 0.50), (0.28, 0.55), (0.4, 0.88), (0.35, 0.6), (0.3, 1.0)] {
            #expect(Ease.spring(0, response: response, damping: damping) == 0)
            for t in stride(from: 3 * response, through: 6 * response, by: 0.01) {
                #expect(abs(Ease.spring(t, response: response, damping: damping) - 1) < 1e-3, "\(response) \(damping) at \(t)")
            }
            #expect(abs(Ease.ringDown(0, response: response, damping: damping) - 1) < 1e-12)
            #expect(abs(Ease.ringDown(3 * response, response: response, damping: damping)) < 1e-3)
        }
    }

    @Test func theThreePrototypeSpringsAgree() {
        // Life and How it works: 1 - e^(-z w t)(cos(wd t) + z w / wd sin(wd t)); the launch: 1 + displacement from -1.
        func stepResponse(_ t: Double, _ response: Double, _ z: Double) -> Double {
            guard t > 0 else { return 0 }
            let w = 2 * Double.pi / response, wd = w * (1 - z * z).squareRoot()
            return 1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
        }
        for (response, damping) in [(0.30, 0.86), (0.34, 0.50), (0.28, 0.55)] {
            let spring = Ease.Spring(response: response, damping: damping)
            for t in stride(from: 0.0, through: 2.0, by: 0.001) {
                let a = Ease.spring(t, response: response, damping: damping)
                #expect(abs(a - spring.value(t)) < 1e-9, "value \(response) \(damping) \(t)")
                #expect(abs(a - stepResponse(t, response, damping)) < 1e-9, "closed form \(response) \(damping) \(t)")
            }
        }
    }

    @Test func aSpringKeepsItsStartingVelocity() {
        // The launch's click: released at rest with a kick, the displacement leaves at the given speed.
        let spring = Ease.Spring(response: 0.30, damping: 0.55)
        let dt = 1e-6
        let v = (spring.displacement(dt, from: 0, velocity: -1.1) - spring.displacement(0, from: 0, velocity: -1.1)) / dt
        #expect(abs(v + 1.1) < 1e-3)
        #expect(spring.displacement(0, from: 0.4) == 0.4)
        #expect(abs(spring.displacement(2, from: 0.4, velocity: -1.1)) < 1e-4)
    }

    @Test func anImpulsePeaksAtOneAndSettles() {
        for (response, damping) in [(0.30, 0.50), (0.34, 0.45), (0.34, 0.62)] {
            var peak = 0.0
            for t in stride(from: 0.0, through: 2.0, by: 0.0005) { peak = max(peak, Ease.impulse(t, response: response, damping: damping)) }
            #expect(abs(peak - 1) < 1e-3, "\(response) \(damping) peaks at \(peak)")
            #expect(Ease.impulse(0, response: response, damping: damping) == 0)
            #expect(abs(Ease.impulse(4 * response, response: response, damping: damping)) < 0.02)
        }
    }

    @Test func anEnvelopeRisesHoldsAndFalls() {
        #expect(Ease.envelope(0.5, start: 1, rise: 0.2, end: 3, fall: 0.3) == 0)
        #expect(abs(Ease.envelope(2, start: 1, rise: 0.2, end: 3, fall: 0.3) - 1) < 1e-9)
        #expect(Ease.envelope(3.5, start: 1, rise: 0.2, end: 3, fall: 0.3) == 0)
        #expect(Ease.envelope(1.1, start: 1, rise: 0.2, end: 3, fall: 0.3) > 0.5)
        #expect(abs(Ease.envelope(3, start: 1, rise: 0.2, end: 3, fall: 0.3)) < 1e-9)
    }

    @Test func anArcPathMovesAtAnEvenSpeed() {
        let path = ArcPath(CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 160), CGPoint(x: 220, y: -60), CGPoint(x: 260, y: 140))
        #expect(path.point(atFraction: 0) == path.p0)
        #expect(hypot(path.point(atFraction: 1).x - path.p3.x, path.point(atFraction: 1).y - path.p3.y) < 1e-9)
        let n = 120
        let points = (0...n).map { path.point(atFraction: Double($0) / Double(n)) }
        let steps = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let spread = (steps.max() ?? 0) - (steps.min() ?? 0)
        #expect(spread < 0.5, "steps differ by \(spread) pt")
        #expect(abs(steps.reduce(0, +) - path.length) < 0.5)
        let tangent = path.tangent(atFraction: 0.5)
        #expect(abs(hypot(tangent.dx, tangent.dy) - 1) < 1e-9)
        #expect(path.segment(from: 0.2, to: 0.6, steps: 10).count == 11)
        #expect(path.segment(from: 0.6, to: 0.2).isEmpty)
    }

    @Test func theDiceAreFixed() {
        // The same seed, index and stream give the same number on every run, in 0..<1.
        #expect(Dice.unit(7, 3, 1) == Dice.unit(7, 3, 1))
        #expect(Dice.unit(7, 3, 1) != Dice.unit(7, 3, 2))
        #expect(Dice.hash01(3, 5, 1) == Dice.hash01(3, 5, 1))
        var seen = Set<Int>()
        for i in 0..<2000 {
            let u = Dice.unit(7, UInt64(i), 1), h = Dice.hash01(i % 16, i / 16, 0)
            #expect((0..<1).contains(u) && (0..<1).contains(h))
            seen.insert(Int(u * 10))
        }
        #expect(seen.count == 10)
        // Pinned values: a change of generator would change every idle schedule and every gather.
        #expect(abs(Dice.unit(7, 0, 1) - Self.pinnedUnit) < 1e-15)
    }

    /// SplitMix64 of (7, 0, 1), computed once by the prototype.
    static let pinnedUnit: Double = {
        var z: UInt64 = 7 &+ 0 &* 0x9E3779B97F4A7C15 &+ 1 &* 0xD1B54A32D192ED03
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }()
}
