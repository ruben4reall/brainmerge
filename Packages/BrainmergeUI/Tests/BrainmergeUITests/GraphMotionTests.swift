import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The memory graph's motion: a hover that fades instead of strobing, zoom and Fit that glide, a first read that blooms
/// from each project's hub, pulses that ripple out and settle.
@MainActor @Suite struct GraphMotionTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func brain(_ home: TempHome) throws -> Brain { try MemoryGraphModelTests().brain(home) }

    // MARK: M7, hover

    /// A memory fades a quarter of the way per frame (about 180 ms to 95%), to 0.28 for what is unrelated and half its
    /// threads; a vault keeps Obsidian's tenth.
    @Test func aMemoryHoverFadesInsteadOfStrobing() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        let unrelated = "memory/mobile-app/project_launch.md"
        model.hover("project:website")
        #expect(model.focus?.contains(unrelated) == false)
        #expect(model.isMoving)
        model.tick()
        #expect(abs(model.fade(unrelated) - (0.75 + 0.28 * 0.25)) < 1e-9)
        #expect(abs(model.lineFade - (0.75 + 0.5 * 0.25)) < 1e-9)
        for _ in 0..<11 { model.tick() }   // 12 frames, 200 ms: 95% of the way
        #expect(model.fade(unrelated) - 0.28 < 0.05 * 0.72)
        for _ in 0..<60 { model.tick() }
        #expect(model.fade(unrelated) == 0.28 && model.fade("project:website") == 1 && model.lineFade == 0.5)
        // Reduce Motion: at once.
        model.reduceMotion = true
        model.pointerLeft()
        model.tick()
        #expect(model.fade(unrelated) == 1 && model.lineFade == 1)
    }

    /// Moving from one bubble to the next crosses empty space: within 80 ms the focus holds, so the graph never relights.
    @Test func movingBetweenBubblesKeepsTheFocus() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.hover("project:website")
        model.hover(nil)
        #expect(model.hovered == "project:website")
        model.hover("memory/mobile-app/project_launch.md")
        #expect(model.hovered == "memory/mobile-app/project_launch.md")
        // Left for good: cleared once the grace is over.
        model.hover(nil)
        for _ in 0..<100 where model.hovered != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.hovered == nil)
        #expect(MemoryGraphModel.hoverGrace == 0.08)
        // Leaving the graph clears at once.
        model.hover("project:website")
        model.pointerLeft()
        #expect(model.hovered == nil)
    }

    /// The pointer keeps moving over empty space after leaving a bubble: each move reports no bubble again, and the grace
    /// still ends 80 ms after the pointer left, not 80 ms after it rests.
    @Test func movingOverEmptySpaceDoesNotStretchTheGrace() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.hover("project:website")
        // About a second of pointer moves, one a frame: each comes well within the grace of the one before.
        var cleared = false
        for _ in 0..<60 {
            model.hover(nil)
            if model.hovered == nil { cleared = true; break }
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(cleared)
    }

    // MARK: M8, zoom and Fit

    /// The zoom buttons glide 0.2 s on the ease-out, the scale geometric about the view's center.
    @Test func zoomGlidesGeometricallyAboutTheCenter() {
        var from = GraphCamera(); from.center = CGPoint(x: 30, y: -10); from.scale = 1
        var to = from; to.scale = 1.25
        let tween = CameraTween(from: from, to: to, kind: .zoom, start: start)
        #expect(tween.duration == 0.2)
        #expect(tween.camera(at: start) == from)
        #expect(tween.camera(at: start.addingTimeInterval(0.2)) == to && tween.isOver(at: start.addingTimeInterval(0.2)))
        let mid = tween.camera(at: start.addingTimeInterval(0.1))
        let e = Ease.out(0.5)
        #expect(abs(Double(mid.scale) - pow(1.25, e)) < 1e-6)   // a date's precision, not the curve's
        #expect(mid.center == from.center)
    }

    /// Fit glides 0.35 s on the in-out curve, on the center and the logarithm of the scale.
    @Test func fitGlidesOnCenterAndLogScale() {
        var from = GraphCamera(); from.center = .zero; from.scale = 0.5
        var to = GraphCamera(); to.center = CGPoint(x: 100, y: 40); to.scale = 2
        let tween = CameraTween(from: from, to: to, kind: .fit, start: start)
        #expect(tween.duration == 0.35)
        let mid = tween.camera(at: start.addingTimeInterval(0.175))
        let e = Ease.inOut(0.5)
        #expect(abs(Double(mid.scale) - 0.5 * pow(4, e)) < 1e-4)   // geometric: at e = 0.5 it would be 1, the middle of 0.5 and 2
        #expect(abs(Double(mid.center.x) - 100 * e) < 1e-3 && abs(Double(mid.center.y) - 40 * e) < 1e-3)
        #expect(tween.camera(at: start.addingTimeInterval(1)) == to)
    }

    /// A zoom click during a Fit glide goes on toward the Fit's center too, instead of holding the center and jumping
    /// there when the zoom ends.
    @Test func aZoomChainedOnAFitGlidesTheCenterToo() {
        var from = GraphCamera(); from.center = .zero; from.scale = 1
        var to = GraphCamera(); to.center = CGPoint(x: 100, y: 40); to.scale = 1.25
        let tween = CameraTween(from: from, to: to, kind: .zoom, start: start)
        let mid = tween.camera(at: start.addingTimeInterval(0.1))
        let e = Ease.out(0.5)
        #expect(abs(Double(mid.center.x) - 100 * e) < 1e-3 && abs(Double(mid.center.y) - 40 * e) < 1e-3)
        let late = tween.camera(at: start.addingTimeInterval(0.199))
        #expect(abs(Double(late.center.x) - 100) < 1)
    }

    /// Buttons ask the model; any gesture that moves the camera cancels the glide; Reduce Motion jumps.
    @Test func aGestureCancelsTheGlide() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false)
        await model.refresh(root: brain.root)
        model.viewSize = CGSize(width: 800, height: 600)
        let before = model.camera.scale
        model.zoom(by: 1.25)
        #expect(model.isMoving && model.camera.scale == before)
        model.camera.center = CGPoint(x: 999, y: 999)   // a drag
        model.tick()
        #expect(model.camera.center == CGPoint(x: 999, y: 999) && model.camera.scale == before)
        model.reduceMotion = true
        model.zoom(by: 2)
        #expect(abs(model.camera.scale - before * 2) < 1e-9)
    }

    // MARK: E14, the first read blooms

    /// Each note starts on its project's hub and travels out on the ease-out, 30 ms later per hop (240 ms at most);
    /// bubbles fade in over 0.2 s; a thread draws once both its ends are past 60% of their way.
    @Test func theBloomStartsEachNoteOnItsHubAndEndsInPlace() {
        let ids = ["project:a", "n1", "n2", "lonely"]
        let positions = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 50, y: 50)]
        let bloom = GraphBloom(ids: ids, links: [(0, 1), (1, 2)], positions: positions, start: start)
        #expect(bloom.delays == [0, 0.03, 0.06, 0])
        #expect(bloom.position(1, target: positions[1], elapsed: 0) == positions[0])
        #expect(bloom.position(2, target: positions[2], elapsed: 0.05) == positions[0])
        #expect(bloom.position(3, target: positions[3], elapsed: 0) == positions[3])   // no hub: fades in where it is
        #expect(bloom.position(0, target: positions[0], elapsed: 0) == positions[0])
        for i in 0..<4 { #expect(bloom.position(i, target: positions[i], elapsed: bloom.duration) == positions[i]) }
        #expect(bloom.opacity(1, elapsed: 0.03) == 0 && bloom.opacity(1, elapsed: 0.24) == 1)
        #expect(bloom.edgeOpacity(0, 1, elapsed: 0.05) == 0)
        #expect(bloom.edgeOpacity(0, 1, elapsed: bloom.duration) == 1)
        #expect(abs(bloom.duration - (0.06 + 0.65)) < 1e-9)
        // A long chain waits 240 ms at most.
        let chain = (0...20).map { $0 == 0 ? "project:x" : "c\($0)" }
        let far = GraphBloom(ids: chain, links: (0..<20).map { ($0, $0 + 1) }, positions: chain.indices.map { CGPoint(x: $0, y: 0) }, start: start)
        #expect(far.delays.max() == 0.24)
    }

    /// The first read of a memory settles out of sight, frames the camera once, then blooms; a later read never does.
    @Test func theFirstReadOfAMemoryBlooms() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false, blooms: true)
        model.viewSize = CGSize(width: 800, height: 600)
        await model.refresh(root: brain.root)
        #expect(model.awaitingFirstLayout)
        while let task = model.bloomTask { await task.value }
        #expect(!model.awaitingFirstLayout)
        let bloom = try #require(model.bloom)
        #expect(model.fitted && model.layout.alpha < 0.05)
        let note = try #require(model.layout.indexOf("memory/website/decision_pricing.md"))
        let hub = try #require(model.layout.indexOf("project:website"))
        #expect(model.drawnPosition(at: note, now: bloom.start) == model.layout.position(at: hub))
        #expect(model.drawnPosition(at: note, now: bloom.start.addingTimeInterval(bloom.duration + 0.001)) == model.layout.position(at: note))
        // A new note later: no bloom again.
        try MemoryGraphModelTests().write(brain.root, "memory/website/feedback_tone.md", "Plain words.\n")
        await model.refresh(root: brain.root)
        #expect(model.bloomTask == nil && !model.awaitingFirstLayout)
    }

    /// Reduce Motion: no bloom; the graph settles out of sight and appears in place, fading in 0.15 s.
    @Test func reduceMotionAppearsInPlace() async throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try brain(home)
        let model = MemoryGraphModel(animates: false, blooms: true)
        model.reduceMotion = true
        await model.refresh(root: brain.root)
        #expect(model.awaitingFirstLayout)
        while let task = model.settleTask { await task.value }
        #expect(model.bloom == nil && !model.awaitingFirstLayout && model.revealedAt != nil)
    }

    // MARK: E15, pulses

    /// A ring from r+3 to r+20 over 1.2 s (radius eased out cubic, opacity 0.8 (1 - t) squared); a save by an account
    /// rings twice, 0.18 s apart, and pops its bubble; the halo lasts 2.6 s.
    @Test func pulsesRippleOutAndSettle() {
        #expect(GraphPulse.rings(elapsed: 0, saved: false) == [GraphPulse.Ring(offset: 3, opacity: 0.8)])
        #expect(GraphPulse.rings(elapsed: 0.1, saved: true).count == 1)
        #expect(GraphPulse.rings(elapsed: 0.2, saved: true).count == 2)
        let half = GraphPulse.rings(elapsed: 0.6, saved: false)[0]
        #expect(abs(half.offset - (3 + 17 * (1 - pow(0.5, 3)))) < 1e-9)
        #expect(abs(half.opacity - 0.8 * 0.25) < 1e-9)
        #expect(GraphPulse.rings(elapsed: 1.2, saved: false).isEmpty)
        #expect(GraphPulse.rings(elapsed: 1.4, saved: true).isEmpty)
        #expect(GraphPulse.bump(elapsed: 0) == 0 && GraphPulse.bump(elapsed: 0.09) == 1)
        #expect(abs(GraphPulse.bump(elapsed: 1.0)) < 0.02)
        #expect((0..<120).map { GraphPulse.bump(elapsed: 0.09 + Double($0) / 120) }.min()! < 0)   // it settles like a hop
        #expect(GraphPulse.haloOpacity(elapsed: 0) == 0.35 && GraphPulse.haloOpacity(elapsed: 2.6) == 0)
        #expect(GraphPulse.lineWidth == 1.5 && MemoryGraphModel.pulseDuration == 2.6)
    }
}
