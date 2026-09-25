import Foundation
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

    // MARK: The walk of the launch splash

    /// The feet's row in the walk: the grid gets one row of headroom above, so the body can bob up.
    let ground = Creature.rows
    func onRow(_ pixels: [Creature.Pixel], _ y: Int) -> [Int] { pixels.filter { $0.y == y }.map(\.x).sorted() }
    func mirrored(_ pixels: [Creature.Pixel]) -> Set<Creature.Pixel> {
        Set(pixels.map { Creature.Pixel(x: Creature.columns - 1 - $0.x, y: $0.y) })
    }

    @Test func theWalkHasFourFramesAndLoops() {
        #expect(Creature.walkCycle == 4)
        for i in -8..<8 { #expect(Creature.walkFrame(i) == Creature.walkFrame(i + 4)) }
        #expect(Creature.walkFrame(-1) == Creature.walkFrame(3))
        #expect(Creature.walkFrame(1) != Creature.walkFrame(0))
        #expect(Creature.walkFrame(3) != Creature.walkFrame(1))
        #expect(Creature.walkRows == Creature.rows + 2)
    }

    @Test func frameZeroIsTheStillCreatureOneRowLower() {
        let still = Creature.walkFrame(0)
        #expect(still.body.count == 120)
        #expect(Set(still.body) == Set(Creature.bodyPixels().map { Creature.Pixel(x: $0.x, y: $0.y + 1) }))
        #expect(still.eyes == Creature.eyes(for: .awake).map { Creature.Eye(x: $0.x, y: $0.y + 1, height: $0.height) })
        #expect(onRow(still.body, ground) == [2, 5, 10, 13])
        #expect(Creature.walkFrame(2) == still)
    }

    @Test func passingFramesLiftOppositeLegsAndMirrorEachOther() {
        let a = Creature.walkFrame(1), b = Creature.walkFrame(3)
        #expect(a.body.count == 122 && b.body.count == 122)
        // The body is up one row; two legs stay planted and stretch to the ground, the other two are lifted one row.
        #expect(onRow(a.body, ground) == [5, 13])
        #expect(onRow(a.body, ground - 1) == [2, 5, 10, 13])
        #expect(onRow(b.body, ground) == [2, 10])
        #expect(Set(b.body) == mirrored(a.body))
        #expect(a.eyes == Creature.eyes(for: .awake))
        #expect(Set(b.eyes.map { Creature.Pixel(x: $0.x, y: $0.y) }) == mirrored(a.eyes.map { Creature.Pixel(x: $0.x, y: $0.y) }))
    }

    @Test func feetNeverLeaveTheGroundAndTheShadowFollows() {
        for i in 0..<Creature.walkCycle {
            let frame = Creature.walkFrame(i)
            #expect(onRow(frame.body, ground).count >= 2, "frame \(i) floats")
            #expect(frame.body.allSatisfy { (0..<Creature.columns).contains($0.x) && (0...ground).contains($0.y) }, "frame \(i) leaves the grid")
            #expect(frame.shadow.allSatisfy { $0.y == ground + 1 }, "frame \(i): the shadow is under the feet")
            #expect(ground + 1 < Creature.walkRows)
        }
        // Wide on contact, narrower while the body is up.
        #expect(Creature.walkFrame(0).shadow.map(\.x).sorted() == Array(2...13))
        #expect(Creature.walkFrame(1).shadow.map(\.x).sorted() == Array(3...12))
        #expect(Creature.walkFrame(3).shadow.map(\.x).sorted() == Array(3...12))
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

    @Test func theGridStaysReadableByTheBrandScript() throws {
        // scripts/make-brand.swift keeps every line of CreatureView.swift that is a quoted 16-character string of X and dots,
        // and needs exactly 11: the walk must be computed from the grid, never drawn as new strings of that shape.
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
