import Testing
@testable import BrainmergeUI

@Suite struct SmokeTests {
    @Test func versionIsSet() {
        #expect(BrainmergeUIInfo.version == "0.5.0")
    }
}
