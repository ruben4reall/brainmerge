import AppKit
import SwiftUI
import Testing
@testable import BrainmergeUI

@MainActor @Suite struct CreatureViewTests {
    /// The view takes exactly the grid's room in a layout (16 by 11 cells): its canvas overflows for hops and sparkles
    /// without growing the sidebar row or the onboarding step.
    @Test func theLayoutIsTheGridWhateverTheCanvas() {
        for (size, unit) in [(CGFloat(32), CGFloat(2)), (48, 3), (64, 4)] {
            for state in [CreatureState.awake, .asleep, .glowing] {
                let host = NSHostingView(rootView: CreatureView(state: state, size: size))
                #expect(host.fittingSize == CGSize(width: 16 * unit, height: 11 * unit), "\(size) \(state): \(host.fittingSize)")
            }
        }
    }

    @Test func thePlacesUseTheirSizes() throws {
        // Sidebar 32 (2 pt cells, companion), welcome 64 (4 pt, stage), All set 48 (3 pt, stage).
        let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        let root = try String(contentsOf: screens.appending(path: "RootView.swift"), encoding: .utf8)
        let onboarding = try String(contentsOf: screens.appending(path: "OnboardingView.swift"), encoding: .utf8)
        #expect(root.contains("CreatureView(state: state, size: 32"))
        #expect(onboarding.contains("CreatureView(state: .awake, size: 64, profile: .stage"))
        #expect(onboarding.contains("CreatureView(state: .awake, size: 48, profile: .stage, events: [CreatureStamp(.memorySaved, at: 0.35)]"))
    }

    @Test func noAuraOrGlowAroundTheCreature() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Design/CreatureView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(!source.contains("AuraView") && !source.contains("glowOpacity") && !source.contains(".blur("))
        #expect(!source.contains(".animation("))
    }
}
