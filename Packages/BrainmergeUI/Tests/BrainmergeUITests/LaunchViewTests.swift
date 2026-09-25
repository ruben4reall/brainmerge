import CoreGraphics
import Testing
@testable import BrainmergeUI

@Suite struct LaunchViewTests {
    @Test func theCreatureSitsOnWholePointsJustAboveTheCenter() {
        // Odd and fractional window sizes too: a half-point origin blurs the pixel edges on a 1x display.
        for size in [CGSize(width: 960, height: 640), CGSize(width: 1001, height: 677), CGSize(width: 1280.5, height: 803.5)] {
            let frame = LaunchView.creatureFrame(in: size)
            #expect(frame.width == CGFloat(Creature.columns) * Theme.Launch.unit)
            #expect(frame.height == CGFloat(Creature.walkRows) * Theme.Launch.unit)
            #expect(frame.minX == frame.minX.rounded() && frame.minY == frame.minY.rounded(), "\(size)")
            #expect(abs(frame.midX - size.width / 2) <= 1)
            #expect(abs(frame.midY - (size.height / 2 - Theme.Launch.lift)) <= 1)
        }
    }
}
