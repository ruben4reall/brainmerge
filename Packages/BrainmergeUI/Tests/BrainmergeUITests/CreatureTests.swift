import Foundation
import SwiftUI
import Testing
@testable import BrainmergeUI

@Suite struct CreatureTests {
    @Test func bodyHasTheExpectedPixelsAndIsSymmetric() {
        let pixels = Creature.bodyPixels()
        #expect(pixels.count == 120)
        for p in pixels { #expect(pixels.contains(Creature.Pixel(x: Creature.columns - 1 - p.x, y: p.y))) }
        #expect(pixels.contains(Creature.Pixel(x: 0, y: 3)) && !pixels.contains(Creature.Pixel(x: 0, y: 0)))
        #expect(pixels.contains(Creature.Pixel(x: 2, y: 10)) && !pixels.contains(Creature.Pixel(x: 3, y: 10)))
    }
    @Test func eyesOpenWhenAwakeAndClosedWhenAsleep() {
        let awake = Creature.eyes(for: .awake)
        #expect(awake.map(\.x) == [4, 11] && awake.allSatisfy { $0.y == 1 && $0.height == 1 })
        let asleep = Creature.eyes(for: .asleep)
        #expect(asleep.map(\.x) == [4, 11] && asleep.allSatisfy { $0.y == 2 && $0.height < 0.5 })
        #expect(Creature.eyes(for: .glowing) == awake)
    }

    // MARK: Helpers

    static func unitRect(_ p: Creature.Pixel) -> CGRect { CGRect(x: p.x, y: p.y, width: 1, height: 1) }
    /// The unit cells a list of whole-cell rectangles covers (a stretched leg is one taller rectangle).
    static func pixels(_ rects: [CGRect]) -> Set<Creature.Pixel> {
        var out = Set<Creature.Pixel>()
        for r in rects {
            for y in Int(r.minY.rounded(.down))..<Int(r.maxY.rounded(.up)) {
                for x in Int(r.minX.rounded(.down))..<Int(r.maxX.rounded(.up)) { out.insert(Creature.Pixel(x: x, y: y)) }
            }
        }
        return out
    }
    static func onRow(_ pixels: Set<Creature.Pixel>, _ y: Int) -> [Int] { pixels.filter { $0.y == y }.map(\.x).sorted() }
    static func mirrored(_ pixels: Set<Creature.Pixel>) -> Set<Creature.Pixel> {
        Set(pixels.map { Creature.Pixel(x: Creature.columns - 1 - $0.x, y: $0.y) })
    }

    // MARK: The pose

    @Test func restPoseIsTheGrid() {
        #expect(Creature.cells(for: .rest) == Creature.bodyPixels().map(Self.unitRect))
        let eyes = Creature.eyes(for: .awake).map { CGRect(x: CGFloat($0.x), y: CGFloat($0.y), width: 1, height: $0.height) }
        #expect(Creature.eyeRects(for: .rest) == eyes)
        #expect(Creature.Pose.rest == Creature.Pose())
    }

    @Test func asleepPoseMatchesTheAsleepEyes() {
        let eyes = Creature.eyes(for: .asleep)
        let rects = Creature.eyeRects(for: .asleep)
        #expect(rects.count == eyes.count)
        for (rect, eye) in zip(rects, eyes) {
            #expect(rect.minX == CGFloat(eye.x) && abs(rect.minY - CGFloat(eye.y)) < 1e-9 && abs(rect.height - eye.height) < 1e-9)
        }
        #expect(Creature.cells(for: .asleep) == Creature.cells(for: .rest))
    }

    @Test func armsTakeTheirPosesMirrored() {
        var pose = Creature.Pose()
        pose.armRight = .lift1
        let right = Self.pixels(Creature.cells(for: pose))
        #expect(Self.onRow(right, 2) == Array(2...15) && Self.onRow(right, 5) == [0, 1] + Array(2...13))
        pose.armRight = .rest; pose.armLeft = .lift1
        #expect(Self.pixels(Creature.cells(for: pose)) == Self.mirrored(right))
        // Every pose keeps six pixels an arm.
        for arm in [ArmPose.rest, .lift1, .up, .out] { #expect(arm.pixels.count == 6) }
    }

    @Test func armsNeverTouchTheHead() {
        // Raised arms leave a column of air beside the head, so they read as arms, never as a wider head.
        for arm in [ArmPose.up, .out] {
            var pose = Creature.Pose()
            pose.armLeft = arm; pose.armRight = arm
            let pixels = Self.pixels(Creature.cells(for: pose))
            for y in 0...2 {
                #expect(!pixels.contains(Creature.Pixel(x: 14, y: y)), "\(arm) touches the head at row \(y)")
                #expect(!pixels.contains(Creature.Pixel(x: 1, y: y)), "\(arm) (left) touches the head at row \(y)")
            }
        }
        // The widest reaches: `up` to column 16, `out` to column 17 (and -2 on the left).
        #expect(ArmPose.up.pixels.map(\.x).max() == 16 && ArmPose.out.pixels.map(\.x).max() == 17)
    }

    @Test func legsLiftTuckAndStretch() {
        var pose = Creature.Pose()
        pose.legsTucked = true
        #expect(Self.onRow(Self.pixels(Creature.cells(for: pose)), 10).isEmpty)
        #expect(Self.onRow(Self.pixels(Creature.cells(for: pose)), 9) == [2, 5, 10, 13])
        pose = Creature.Pose()
        pose.raise = 1
        pose.liftedLegs = [true, false, false, false]
        let pixels = Self.pixels(Creature.cells(for: pose))
        // The body is one row up; the planted legs stretch to the ground, the lifted one stops a row short.
        #expect(Self.onRow(pixels, 10) == [5, 10, 13])
        #expect(Self.onRow(pixels, 7) == [2, 5, 10, 13])
        #expect(Self.onRow(pixels, 2) == Array(0...15))
        #expect(Creature.eyeRects(for: pose).allSatisfy { $0.minY == 0 })
    }

    @Test func eyesLookAndGrowUpward() {
        var pose = Creature.Pose()
        pose.look = -1
        #expect(Creature.eyeRects(for: pose).map(\.minX) == [3, 10])
        pose.look = 0; pose.eyeHeight = 1.35
        // The startle's wide eyes grow upward from the same bottom edge, never into row 0's top.
        #expect(Creature.eyeRects(for: pose).allSatisfy { abs($0.maxY - 2) < 1e-9 && abs($0.minY - 0.65) < 1e-9 })
    }

    @Test func noEyesAtHeightZero() {
        // The launch's gather: a cloud of pixels has no eyes yet; the pose says so with an eye height of 0.
        var pose = Creature.Pose()
        pose.eyeHeight = 0
        #expect(Creature.eyeRects(for: pose).isEmpty)
        #expect(Creature.geometry(for: pose, feet: CGPoint(x: 20, y: 22), unit: 2, displayScale: 2).eyes.isEmpty)
        #expect(Creature.cells(for: pose) == Creature.cells(for: .rest))
    }

    @Test func gatheringPixelsTravelFromHome() {
        // The launch's gather: one state per body pixel, in `bodyPixels()` order.
        var pose = Creature.Pose()
        var states = Array(repeating: PixelState(), count: Creature.bodyPixels().count)
        states[0] = PixelState(dx: 2, dy: -1, scale: 0.5, opacity: 0.4)
        pose.pixels = states
        let cells = Creature.cells(for: pose)
        let home = Creature.bodyPixels()[0]
        #expect(cells[0] == CGRect(x: CGFloat(home.x) + 2.25, y: CGFloat(home.y) - 0.75, width: 0.5, height: 0.5))
        #expect(Array(cells.dropFirst()) == Array(Creature.cells(for: .rest).dropFirst()))
        #expect(!states[0].isHome && PixelState().isHome)
    }

    // MARK: Drawing on whole device pixels

    @Test func theCellIsWholeDevicePixels() {
        #expect(Creature.unit(size: 32, displayScale: 2) == 2)
        #expect(Creature.unit(size: 48, displayScale: 2) == 3)
        #expect(Creature.unit(size: 64, displayScale: 1) == 4)
        // A size that is not a multiple of 16 is floored to whole device pixels, never below one.
        #expect(Creature.unit(size: 28, displayScale: 2) == 1.5)
        #expect(Creature.unit(size: 28, displayScale: 1) == 1)
        #expect(Creature.unit(size: 4, displayScale: 2) == 0.5)
    }

    @Test func breathAndOffsetsLandOnDevicePixels() {
        // At scale 1 and no rotation every edge of the body and the eyes lands on a device pixel, whatever the breath,
        // the offset or the feet: a sprite never blurs at rest or while breathing.
        for displayScale in [CGFloat(1), 2] {
            for breath in 0...2 {
                for offset in [CGVector.zero, CGVector(dx: 0.37, dy: -1.21)] {
                    var pose = Creature.Pose()
                    pose.breath = breath; pose.offset = offset
                    let g = Creature.geometry(for: pose, feet: CGPoint(x: 40.3, y: 30.6), unit: 2, displayScale: displayScale)
                    for rect in g.body.map(\.rect) + g.eyes {
                        for edge in [rect.minX, rect.minY, rect.maxX, rect.maxY] {
                            #expect(abs(edge * displayScale - (edge * displayScale).rounded()) < 1e-9, "scale \(displayScale) breath \(breath)")
                        }
                    }
                    // Breathing lifts the body above the legs by whole device pixels; the feet stay on the ground.
                    let rest = Creature.geometry(for: Creature.Pose(offset: offset), feet: CGPoint(x: 40.3, y: 30.6), unit: 2, displayScale: displayScale)
                    let top = g.body.map(\.rect.minY).min()!, restTop = rest.body.map(\.rect.minY).min()!
                    #expect(abs((restTop - top) * displayScale - CGFloat(breath)) < 1e-9)
                    #expect(g.body.map(\.rect.maxY).max() == rest.body.map(\.rect.maxY).max())
                }
            }
        }
    }

    @Test func theAsleepDashIsNeverThinnerThanADevicePixel() {
        let g = Creature.geometry(for: .asleep, feet: CGPoint(x: 20, y: 22), unit: 1, displayScale: 1)
        #expect(g.eyes.allSatisfy { $0.height >= 1 })
    }

    // MARK: The walk

    @Test func theWalkHasFourFramesAndLoops() {
        #expect(Creature.walkCycle == 4)
        for i in -8..<8 { #expect(Creature.walkFrame(i) == Creature.walkFrame(i + 4)) }
        #expect(Creature.walkFrame(-1) == Creature.walkFrame(3))
        #expect(Creature.walkFrame(1) != Creature.walkFrame(0))
        #expect(Creature.walkFrame(3) != Creature.walkFrame(1))
    }

    @Test func walkContactFramesAreRest() {
        #expect(Creature.walkFrame(0) == .rest)
        #expect(Creature.walkFrame(2) == .rest)
    }

    @Test func passingFramesLiftOppositeLegsSwingAnArmAndMirrorEachOther() {
        let a = Creature.walkFrame(1), b = Creature.walkFrame(3)
        #expect(a.raise == 1 && b.raise == 1)
        #expect(a.armRight == .lift1 && a.armLeft == .rest && b.armLeft == .lift1 && b.armRight == .rest)
        let pa = Self.pixels(Creature.cells(for: a)), pb = Self.pixels(Creature.cells(for: b))
        // The body is up one row; two legs stay planted and stretch to the ground, the other two are lifted.
        #expect(Self.onRow(pa, 10) == [5, 13])
        #expect(Self.onRow(pa, 9) == [2, 5, 10, 13])
        #expect(Self.onRow(pb, 10) == [2, 10])
        #expect(pb == Self.mirrored(pa))
        // The eyes ride up with the body.
        #expect(Creature.eyeRects(for: a).allSatisfy { $0.minY == 0 })
        for i in 0..<Creature.walkCycle {
            let pixels = Self.pixels(Creature.cells(for: Creature.walkFrame(i)))
            #expect(Self.onRow(pixels, 10).count >= 2, "frame \(i) floats")
            // The walk's headroom: the body bobs up one row above the grid on passing frames, never more.
            #expect(pixels.allSatisfy { (0..<Creature.columns).contains($0.x) && (-1...10).contains($0.y) }, "frame \(i) leaves the grid")
            #expect(Self.onRow(pixels, -1).isEmpty == (i % 2 == 0), "frame \(i)")
        }
    }

    @Test func theWalksShadowNarrowsWhileTheBodyIsUp() {
        #expect(Creature.walkShadow(0) == 2...13)
        #expect(Creature.walkShadow(1) == 3...12)
        #expect(Creature.walkShadow(2) == 2...13)
        #expect(Creature.walkShadow(3) == 3...12)
    }

    @Test func theFrameFollowsTheClockOnRealDatesAndFreezes() {
        // Real clock values: dates around 7.8e8 seconds lose precision, and a plain division limps (repeats and skips frames).
        let duration = 0.12
        let start = Date(timeIntervalSinceReferenceDate: 780_000_000.123)
        var stepped = start
        for n in 0..<400 {
            let exact = start.addingTimeInterval(Double(n) * duration)
            #expect(Creature.walkIndex(at: exact, since: start, frameDuration: duration, frozen: false) == n % 4, "tick \(n)")
            #expect(Creature.walkIndex(at: stepped, since: start, frameDuration: duration, frozen: false) == n % 4, "stepped tick \(n)")
            #expect(Creature.walkIndex(at: exact, since: start, frameDuration: duration, frozen: true) == 0)
            stepped = stepped.addingTimeInterval(duration)
        }
        // Between two ticks, the frame of the last tick; before the start, the still frame.
        #expect(Creature.walkIndex(at: start.addingTimeInterval(0.119), since: start, frameDuration: duration, frozen: false) == 0)
        #expect(Creature.walkIndex(at: start.addingTimeInterval(0.30), since: start, frameDuration: duration, frozen: false) == 2)
        #expect(Creature.walkIndex(at: start.addingTimeInterval(-1), since: start, frameDuration: duration, frozen: false) == 0)
    }

    // MARK: The brand script's grid

    @Test func exactlyOneGridLiteral() throws {
        // scripts/make-brand.swift keeps every line of CreatureView.swift that is a quoted 16-character string of X and dots,
        // and needs exactly 11: poses, the walk and sprites are computed or drawn smaller, never as new strings of that shape.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Design/CreatureView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let rows: [String] = source.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") else { return nil }
            let content = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\",")).replacingOccurrences(of: "\",", with: "")
            return content.count == 16 && content.allSatisfy({ $0 == "X" || $0 == "." }) ? content : nil
        }
        #expect(rows.count == 11)
        #expect(rows == Creature.body)
    }
}
