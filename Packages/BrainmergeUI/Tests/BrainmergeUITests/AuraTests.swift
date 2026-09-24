import Foundation
import SwiftUI
import Testing
@testable import BrainmergeUI

@Suite struct AuraTests {
    @Test func oneTurnPerPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(Aura.angle(at: start, period: 6, frozen: false).degrees == 0)
        #expect(Aura.angle(at: start.addingTimeInterval(1.5), period: 6, frozen: false).degrees == 90)
        #expect(Aura.angle(at: start.addingTimeInterval(6), period: 6, frozen: false).degrees == 0)
    }
    @Test func reducedMotionFreezesTheAngle() {
        let later = Date(timeIntervalSinceReferenceDate: 1234.5)
        #expect(Aura.angle(at: later, period: 6, frozen: true).degrees == 0)
    }
}
