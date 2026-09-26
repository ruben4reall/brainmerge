import Foundation
import Observation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The window's root view is built inside the scenes' body, at every redraw of the scenes: whatever its `init` reads from
/// the model becomes something the scenes depend on, and whatever it changes invalidates them again (at launch that was a
/// loop: the window never showed).
@MainActor @Suite struct RootViewTests {
    @Test func buildingTheWindowReadsAndChangesNothingInTheModel() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let app = OnboardingModelTests().unloadedApp(e)
        let changed = LaunchClockTests.Flag()
        withObservationTracking {
            _ = RootView(model: app)
            _ = RootView(model: app)
        } onChange: { changed.raise() }
        #expect(!changed.raised, "a second window queued work observably")
        await app.launch(minimum: .zero)
        #expect(app.launchPhase == .ready && !app.accounts.isEmpty)
        #expect(!changed.raised, "building the window read the model")
    }

    /// Work queued for the first screen is the model's own business: queuing it never redraws anything.
    @Test func queuingWorkForTheFirstScreenIsNeverObserved() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let app = OnboardingModelTests().unloadedApp(e)
        let changed = LaunchClockTests.Flag()
        withObservationTracking { app.runBeforeReady {} } onChange: { changed.raise() }
        app.runBeforeReady {}
        #expect(!changed.raised)
    }
}
