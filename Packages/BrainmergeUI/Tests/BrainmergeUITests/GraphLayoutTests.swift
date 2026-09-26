import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct GraphLayoutTests {
    func distance(_ layout: GraphLayout, _ a: String, _ b: String) -> CGFloat {
        let p = layout.position(of: a)!, q = layout.position(of: b)!
        return hypot(p.x - q.x, p.y - q.y)
    }

    func settled(_ nodes: [String], _ edges: [(String, String)], forces: GraphForces = .brainmerge) -> GraphLayout {
        var layout = GraphLayout(forces: forces)
        layout.sync(nodes: nodes, edges: edges)
        for _ in 0..<1000 where !layout.isSettled { layout.step() }
        return layout
    }

    func closest(_ layout: GraphLayout, _ ids: [String]) -> CGFloat {
        var best = CGFloat.infinity
        for (i, a) in ids.enumerated() { for b in ids[(i + 1)...] { best = min(best, distance(layout, a, b)) } }
        return best
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

    @Test func aRewiredLinkWakesTheSimulation() {
        var layout = settled(["a", "b", "c", "d"], [("a", "b"), ("c", "d")])
        #expect(layout.isSettled)
        layout.sync(nodes: ["a", "b", "c", "d"], edges: [("a", "c"), ("b", "d")])
        #expect(!layout.isSettled)
    }

    @Test func rectanglesOverlapOnlyWithOthers() {
        var index = RectIndex()
        index.insert(CGRect(x: 0, y: 0, width: 20, height: 10), owner: 1)
        index.insert(CGRect(x: 300, y: 300, width: 20, height: 10), owner: 2)
        #expect(index.intersects(CGRect(x: 15, y: 5, width: 10, height: 10)))
        #expect(!index.intersects(CGRect(x: 15, y: 5, width: 10, height: 10), except: 1))
        #expect(!index.intersects(CGRect(x: 100, y: 100, width: 10, height: 10)))
        #expect(index.intersects(CGRect(x: 250, y: 290, width: 60, height: 20)))
        #expect(!index.intersects(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)))
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

    /// Obsidian's forces from a vault's sliders: its center pull, a repulsion with no cutoff, its link rest length and
    /// strength, a collision radius of 60, and a gentler reheat than Brainmerge's own.
    @Test func obsidianForcesComeFromTheVaultsSliders() {
        let forces = GraphForces.obsidian(ObsidianGraphSettings())
        #expect(abs(forces.center - 0.1) < 1e-9)
        #expect(forces.charge == -1000 && forces.chargeReach == nil)
        #expect(forces.linkDistance == 250 && forces.linkStrength == 1)
        #expect(forces.collideRadius == 60 && forces.collideStrength == 0.5)
        #expect(forces.reheat == 0.3)
        #expect(GraphForces.brainmerge.collideRadius == 0 && GraphForces.brainmerge.chargeReach == 900)
    }

    /// With Obsidian's forces a vault spreads into an even disc: linked notes rest far apart, and the collision force
    /// keeps every pair of centers apart where Brainmerge's own forces let linked notes clump.
    @Test func obsidianForcesSpreadTheGraphAndKeepNotesApart() {
        let ids = (0..<30).map { "n\($0)" }
        let edges = (0..<29).map { ("n\($0)", "n\($0 + 1)") } + (0..<10).map { ("n0", "n\($0 * 3)") }.filter { $0.0 != $0.1 }
        let obsidian = settled(ids, edges, forces: .obsidian(ObsidianGraphSettings()))
        let own = settled(ids, edges)
        #expect(obsidian.isSettled)
        #expect(closest(obsidian, ids) > 90)
        #expect(closest(own, ids) < closest(obsidian, ids))
        #expect(distance(obsidian, "n10", "n11") > 3 * distance(own, "n10", "n11"))
    }

    /// The collision force alone: short links and almost no repulsion would pull linked notes onto each other; the
    /// collision keeps their centers close to two radii (120) apart.
    @Test func collisionsKeepCentersTwoRadiiApart() {
        var s = ObsidianGraphSettings()
        s.linkDistance = 30; s.repelStrength = 0
        let ids = ["a", "b", "c", "d"]
        let edges = [("a", "b"), ("b", "c"), ("c", "d"), ("d", "a"), ("a", "c")]
        var loose = GraphForces.obsidian(s)
        loose.collideRadius = 0
        #expect(closest(settled(ids, edges, forces: loose), ids) < 60)
        #expect(closest(settled(ids, edges, forces: .obsidian(s)), ids) > 100)
    }

    /// A link written both ways is two springs, as in Obsidian: both notes count it twice in their link strength.
    @Test func aMutualLinkIsTwoSprings() {
        var layout = GraphLayout(forces: .obsidian(ObsidianGraphSettings()))
        layout.sync(nodes: ["a", "b", "c"], edges: [("a", "b"), ("b", "a"), ("c", "a")])
        #expect(layout.degree == [3, 2, 1])
        #expect(layout.linkIndices.count == 3)
    }

    @Test func newForcesWakeTheLayoutOnlyWhenTheyChange() {
        var layout = settled(["a", "b", "c"], [("a", "b"), ("b", "c")])
        layout.setForces(.brainmerge)
        #expect(layout.isSettled)
        layout.setForces(.obsidian(ObsidianGraphSettings()))
        #expect(!layout.isSettled && layout.forces.linkDistance == 250)
    }

    /// The first placement is spread to the forces' scale: a vault does not start as a tight knot that explodes.
    @Test func theFirstPlacementFollowsTheLinkDistance() {
        var own = GraphLayout(), obsidian = GraphLayout(forces: .obsidian(ObsidianGraphSettings()))
        let ids = (0..<20).map { "n\($0)" }
        own.sync(nodes: ids, edges: []); obsidian.sync(nodes: ids, edges: [])
        #expect(obsidian.bounds.width > 4 * own.bounds.width)
    }

    @Test func aLargeVaultStepsQuicklyWithObsidiansForces() {
        let nodes = (0..<1500).map { "n\($0)" }
        let edges = (0..<1500).map { ("n\($0)", "n\(($0 * 37 + 11) % 1500)") }
        var layout = GraphLayout(forces: .obsidian(ObsidianGraphSettings()))
        layout.sync(nodes: nodes, edges: edges)
        let start = Date()
        for _ in 0..<10 { layout.step() }
        #expect(Date().timeIntervalSince(start) / 10 < 0.15, "collisions are found through a grid, not by comparing every pair")
    }
}
