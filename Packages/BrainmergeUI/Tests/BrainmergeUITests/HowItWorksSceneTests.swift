import AppKit
import CoreGraphics
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// How it works as a pure function of time: three account windows, one folder on this Mac, a note that goes from one
/// window into the folder and up into the two others. Every beat starts and ends at rest, and the loop has no seam.
@Suite struct HowItWorksSceneTests {
    typealias S = HowItWorksScene

    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
    static func close(_ p: Creature.Pose, _ q: Creature.Pose) -> Bool {
        p.look == q.look && p.armLeft == q.armLeft && p.armRight == q.armRight && p.legsTucked == q.legsTucked
            && p.eyeHeight == q.eyeHeight && close(p.scaleX, q.scaleX) && close(p.scaleY, q.scaleY)
            && close(p.offset.dx, q.offset.dx) && close(p.offset.dy, q.offset.dy)
    }

    // MARK: Ported from the prototype

    @Test func restPoseIsTheGrid() {
        let pose = S.frame(at: 0).creature
        #expect(pose == .rest)
        let grid = Set(Creature.bodyPixels().map { CGRect(x: $0.x, y: $0.y, width: 1, height: 1) })
        #expect(Set(Creature.cells(for: pose)) == grid)
        #expect(Creature.eyeRects(for: pose) == Creature.eyes(for: .awake).map { CGRect(x: $0.x, y: $0.y, width: 1, height: 1) })
    }

    @Test func everyBeatStartsAndEndsAtRest() {
        for b in 0..<3 {
            for tau in [0.0, 0.05, S.beat - 0.12, S.beat - 0.001] {
                let pose = S.frame(at: Double(b) * S.beat + tau).creature
                #expect(pose == .rest, "beat \(b) tau \(tau): \(pose)")
            }
        }
    }

    @Test func theLoopIsSeamless() {
        let end = S.frame(at: S.loop - 1.0 / 120), start = S.frame(at: 0)
        #expect(end.chips.isEmpty && start.chips.isEmpty)
        #expect(end.trails.allSatisfy { $0.opacity < 0.02 } && start.trails.allSatisfy { $0.opacity < 0.02 })
        for w in 0..<3 {
            #expect(end.windows[w].received == start.windows[w].received)
            #expect(end.windows[w].outline < 0.02 && start.windows[w].outline < 0.02)
            #expect(abs(end.windows[w].receivedOpacity - start.windows[w].receivedOpacity) < 0.01)
            #expect(end.windows[w].ring == nil && start.windows[w].ring == nil)
        }
        #expect(abs(end.frontSquash) < 0.005 && abs(start.frontSquash) < 0.005)
        #expect(end.folderFlash < 0.02 && start.folderFlash < 0.02)
    }

    @Test func periodicAndDeterministic() {
        for t in stride(from: 0.0, to: S.loop, by: 0.37) {
            let a = S.frame(at: t), b = S.frame(at: t + 3 * S.loop), again = S.frame(at: t)
            #expect(Self.close(a.creature, b.creature), "t \(t)")
            #expect(a.chips.count == b.chips.count && a.caption == b.caption && a.trails.count == b.trails.count)
            for (x, y) in zip(a.chips, b.chips) {
                #expect(Self.close(x.position.x, y.position.x) && Self.close(x.position.y, y.position.y) && Self.close(x.rotation, y.rotation))
            }
            #expect(a == again)
        }
    }

    @Test func notesStayInsideTheCanvas() {
        for t in stride(from: 0.0, to: S.loop, by: 1.0 / 60) {
            for c in S.frame(at: t).chips {
                #expect(c.position.x > 10 && c.position.x < S.size.width - 10 && c.position.y > 10 && c.position.y < S.size.height - 10,
                        "t \(t): \(c.position)")
            }
        }
    }

    @Test func noteTravelsAtEvenSpeed() {
        for lane in S.lanes {
            let points = (0...20).map { lane.point(atFraction: Double($0) / 20) }
            let steps = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
            #expect((steps.max() ?? 0) - (steps.min() ?? 0) < 0.5)
        }
    }

    @Test func eachNoteReachesBothOtherWindows() {
        for b in 0..<3 {
            let src = S.order[b]
            let f = S.frame(at: Double(b) * S.beat + (S.timing(src: src).copyArrive.max() ?? 0) + 0.2)
            for w in 0..<3 where w != src { #expect(f.windows[w].received == src, "beat \(b) window \(w)") }
            #expect(f.windows[src].received != src)
        }
    }

    @Test func everyBeatFitsItsWindow() {
        for src in 0..<3 {
            let tm = S.timing(src: src)
            // The last copy lands and glows (its rim is gone 0.3 s later), and the beat still has room to rest.
            #expect((tm.copyArrive.max() ?? .infinity) + 0.3 <= S.beat - 0.05, "\(src): \(tm)")
        }
    }

    @Test func captionsAreShortAndHaveNoDashes() {
        var captions = Set<String>()
        for t in stride(from: 0.0, to: S.loop, by: 0.05) { captions.insert(S.frame(at: t).caption) }
        captions.insert(S.still().caption)
        #expect(captions.count == 7)
        for c in captions {
            #expect(!c.contains("\u{2014}") && !c.contains("\u{2013}") && !c.contains(" - "), "\(c)")
            #expect(c.count <= 52, "\(c)")
        }
        #expect(Set(S.captions) == captions)
    }

    @Test func easingEndpoints() {
        for curve in [Ease.out, Ease.inOut, Ease.glide, Ease.ease] { #expect(abs(curve(0)) < 1e-9 && abs(curve(1) - 1) < 1e-9) }
        #expect(abs(Ease.spring(5, response: 0.35, damping: 0.6) - 1) < 1e-4)
        #expect(abs(Ease.impulse(3, response: 0.3, damping: 0.45)) < 1e-4)
    }

    // MARK: The director's corrections

    /// Studio is pink everywhere else (demo home, README captures, the site's Dock): the diagram says the same.
    /// Personal and Studio never sit side by side, Work sits between them.
    @Test func studioIsPink() {
        #expect(S.accounts.map(\.name) == ["Personal", "Work", "Studio"])
        #expect(S.accounts.map(\.tint) == [.orange, .blue, .pink])
        #expect(S.order == [0, 1, 2])
    }

    /// The caption's line box sits at least 4 points under the creature's shadow, and inside the canvas.
    @Test func captionClearsTheShadow() {
        let font = NSFont.systemFont(ofSize: S.captionFontSize)
        let lineHeight = font.ascender - font.descender + font.leading
        let top = S.captionCenter.y - lineHeight / 2
        #expect(top >= S.shadowRect(air: 0).maxY + 4, "caption top \(top), shadow bottom \(S.shadowRect(air: 0).maxY)")
        #expect(S.captionCenter.y + lineHeight / 2 <= S.size.height)
        #expect(S.size == CGSize(width: 520, height: 224))
    }

    // MARK: The still and the shadow

    /// Captures and Reduce Motion: one still that tells the whole story, beat 0 at 1.97 s, the creature at rest.
    @Test func theStillTellsTheWholeStory() {
        let still = S.still()
        #expect(still.caption == "Personal saves a note. Work and Studio can read it.")
        #expect(still.captionOpacity == 1 && still.captionRise == 0)
        // At rest on its exact grid, its eyes one cell toward the copy flying to Work.
        var watching = Creature.Pose.rest
        watching.look = -1
        #expect(still.creature == watching)
        #expect(still.windows[0].outline > 0.99 && still.windows[0].outlineSource == 0)
        #expect(still.trails.contains { $0.lane == 0 && $0.source == 0 && $0.opacity > 0.8 })
        let copies = still.chips.filter { !$0.behindFront }
        #expect(copies.count == 2 && copies.allSatisfy { $0.source == 0 && $0.opacity > 0.9 })
        #expect(still.chips.count == 2)
    }

    /// The shadow is the selection color, 12 cells wide at rest, narrower and lighter in the air.
    @Test func theShadowNarrowsInTheAir() {
        let rest = S.shadowRect(air: 0), high = S.shadowRect(air: 1)
        #expect(rest.width == 12 * S.creatureUnit && rest.height == 3 && rest.midX == S.creatureFeet.x && rest.minY == S.creatureFeet.y + 2)
        #expect(high.width == 8 * S.creatureUnit && high.midX == S.creatureFeet.x)
        #expect(S.shadowOpacity(air: 0) == 1 && abs(S.shadowOpacity(air: 1) - 0.65) < 1e-9)
        // The hop of beats 0 and 2 leaves the ground, 7 points at its apex; the catch of beat 1 never does.
        let hops = (0..<3).map { b in stride(from: 0.0, to: S.beat, by: 1.0 / 240).map { S.air(of: S.frame(at: Double(b) * S.beat + $0).creature) }.max() ?? 0 }
        #expect(hops[0] > 0.99 && hops[2] > 0.99 && hops[1] == 0)
    }

    // MARK: The beat's values (MOTION.md 4.2), pinned

    @Test func theBeatKeepsItsTiming() throws {
        #expect(S.T.lift == 0.56 && S.T.drop == 0.14 && S.T.copyRise == 0.12 && S.T.stagger == 0.09 && S.T.hero == 1.97)
        // Personal's note pops out just before 0.56 s and leaves its window then.
        #expect(S.frame(at: 0.53).chips.isEmpty)
        let popped = try #require(S.frame(at: 0.55).chips.first), leaving = try #require(S.frame(at: 0.56).chips.first)
        let away = try #require(S.frame(at: 0.57).chips.first)
        #expect(leaving.position == popped.position && away.position != leaving.position)
        // Its lane's length gives it 0.74 s of travel: it lands in the folder at 1.445 s, and the copies leave 0.09 s apart.
        let t = S.timing(src: 0)
        #expect(abs(t.landed - 1.4448) < 1e-3 && abs(t.landed - t.arrive - 0.14) < 1e-9)
        #expect(abs(t.copyStart - (t.landed + 0.08)) < 1e-9 && abs(t.copyLeave[1] - t.copyLeave[0] - 0.09) < 1e-9)
        #expect(abs(t.copyArrive[0] - 2.1370) < 1e-3 && abs(t.copyArrive[1] - 2.3777) < 1e-3)
        // The still is beat 0 at 1.97 s.
        var still = S.frame(at: 1.97)
        still.caption = S.still().caption
        #expect(S.still().chips == still.chips && S.still().windows == still.windows)
    }

    @Test func theCreatureHopsSevenPoints() {
        #expect(S.hopHeight == 7)
        var apex = 0.0
        for i in 0...Int(S.beat * 480) { apex = min(apex, S.frame(at: Double(i) / 480).creature.offset.dy * S.creatureUnit) }
        #expect(abs(apex + 7) < 0.01, "apex \(apex) pt")
    }
}
