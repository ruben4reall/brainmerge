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
}
