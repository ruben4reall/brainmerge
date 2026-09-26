import SwiftUI
import Testing
@testable import BrainmergeUI

@MainActor @Suite struct OnboardingViewTests {
    /// Going on, the new page comes in from the right and the old one leaves to the left; going back, the other way round.
    @Test func pagesSlideTheWayTheGuideMoves() {
        #expect(StepSlide.shift(.willAppear, direction: 1) == 24 && StepSlide.shift(.didDisappear, direction: 1) == -24)
        #expect(StepSlide.shift(.willAppear, direction: -1) == -24 && StepSlide.shift(.didDisappear, direction: -1) == 24)
        #expect(StepSlide.shift(.identity, direction: 1) == 0 && StepSlide.shift(.identity, direction: -1) == 0)
    }

    /// How it works is drawn 1:1 inside the step's 520 point column: never scaled, so its 3 point cells stay whole.
    @Test func howItWorksFitsTheColumnAtItsOwnSize() {
        #expect(HowItWorksScene.size.width <= 520)
        #expect(HowItWorksScene.creatureUnit == HowItWorksScene.creatureUnit.rounded())
    }
}
