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

    /// How it works is drawn 1:1 inside the step's column: never scaled nor clipped, so its 3 point cells stay whole.
    /// The page, laid out as the guide lays it out (560 points wide), holds the scene drawn alone, pixel for pixel.
    @Test func howItWorksFitsTheColumnAtItsOwnSize() throws {
        #expect(HowItWorksScene.size == CGSize(width: 520, height: 224))
        #expect(HowItWorksScene.creatureUnit == HowItWorksScene.creatureUnit.rounded())
        let (e, _, onboarding) = try OnboardingModelTests().setup()
        defer { e.home.remove() }
        let page = try #require(HowItWorksViewTests.render(OnboardingView(model: onboarding).howItWorks.frame(width: 560)))
        let alone = try #require(HowItWorksViewTests.render(
            HowItWorksCanvas(frame: HowItWorksScene.frame(at: 0), texts: HowItWorksTexts()).frame(width: 520, height: 224)))
        #expect(alone.pixelsWide == 1040 && alone.pixelsHigh == 448)
        // Centered in the column (20 points each side), under the title: find the row where it sits.
        let match = (0...240).first { y in HowItWorksViewTests.differing(page, alone, at: CGPoint(x: 40, y: y)) < 400 }
        #expect(match != nil, "the scene is not drawn at its own size in the page")
    }
}
