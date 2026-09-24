import Foundation
import Testing
@testable import BrainmergeUI

@Suite struct GraphLayoutTests {
    func distance(_ layout: GraphLayout, _ a: String, _ b: String) -> CGFloat {
        let p = layout.position(of: a)!, q = layout.position(of: b)!
        return hypot(p.x - q.x, p.y - q.y)
    }

    func settled(_ nodes: [String], _ edges: [(String, String)]) -> GraphLayout {
        var layout = GraphLayout()
        layout.sync(nodes: nodes, edges: edges)
        for _ in 0..<600 where !layout.isSettled { layout.step() }
        return layout
    }

    @Test func linkedNotesEndCloserThanUnlinkedOnes() {
        let layout = settled(["a", "b", "c", "d"], [("a", "b"), ("c", "d")])
        #expect(distance(layout, "a", "b") < distance(layout, "a", "c"))
        #expect(distance(layout, "c", "d") < distance(layout, "b", "d"))
        #expect(distance(layout, "a", "c") > 20)   // nothing collapses onto one point
    }

    @Test func theSimulationComesToRest() {
        let layout = settled((0..<40).map { "n\($0)" }, (0..<39).map { ("n\($0)", "n\($0 + 1)") })
        #expect(layout.isSettled)
        #expect(layout.maxSpeed < 0.5)
    }

    @Test func newNotesAppearNextToWhatTheyLinkToAndOthersDoNotMove() {
        var layout = settled(["a", "b", "c"], [("a", "b"), ("b", "c")])
        let before = ["a", "b", "c"].map { layout.position(of: $0)! }
        layout.sync(nodes: ["a", "b", "c", "d"], edges: [("a", "b"), ("b", "c"), ("d", "a")])
        #expect(["a", "b", "c"].map { layout.position(of: $0)! } == before)
        #expect(distance(layout, "d", "a") < 60)
        #expect(!layout.isSettled)   // a change wakes the simulation up
        layout.sync(nodes: ["a", "b"], edges: [("a", "b")])
        #expect(layout.position(of: "c") == nil && layout.position(of: "d") == nil)
    }

    @Test func theSameGraphAlwaysGivesTheSameLayout() {
        let nodes = (0..<25).map { "n\($0)" }, edges = (0..<24).map { ("n\($0)", "n\(($0 * 7) % 25)") }
        let one = settled(nodes, edges), two = settled(nodes, edges)
        #expect(nodes.allSatisfy { one.position(of: $0) == two.position(of: $0) })
    }

    @Test func aDraggedNoteStaysUnderThePointer() {
        var layout = settled(["a", "b"], [("a", "b")])
        layout.drag("a", to: CGPoint(x: 400, y: -300))
        for _ in 0..<30 { layout.step() }
        #expect(layout.position(of: "a") == CGPoint(x: 400, y: -300))
        layout.release("a")
        for _ in 0..<60 { layout.step() }
        #expect(layout.position(of: "a") != CGPoint(x: 400, y: -300))
    }

    @Test func aLargeVaultStepsQuickly() {
        let nodes = (0..<1500).map { "n\($0)" }
        let edges = (0..<1500).map { ("n\($0)", "n\(($0 * 37 + 11) % 1500)") }
        var layout = GraphLayout()
        layout.sync(nodes: nodes, edges: edges)
        let start = Date()
        for _ in 0..<10 { layout.step() }
        #expect(Date().timeIntervalSince(start) / 10 < 0.15, "one step of 1500 notes stays fast even in a debug build (Barnes-Hut, not n squared)")
    }

    @Test func hitTestingFindsTheNoteUnderThePoint() {
        var layout = GraphLayout()
        layout.sync(nodes: ["a"], edges: [])
        let p = layout.position(of: "a")!
        #expect(layout.nearest(to: CGPoint(x: p.x + 3, y: p.y - 2), within: 8) == "a")
        #expect(layout.nearest(to: CGPoint(x: p.x + 50, y: p.y), within: 8) == nil)
    }
}
