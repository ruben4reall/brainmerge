import AppKit
import SwiftUI
import Testing
@testable import BrainmergeUI

/// The view around the scene: its clock, its still, and text laid out once instead of on every frame.
@MainActor @Suite struct HowItWorksViewTests {
    /// Reduce Motion and captures draw the still whatever the clock says; otherwise every visit starts with Personal typing.
    @Test func frozenShowsTheStillAndEveryVisitStartsWithPersonal() {
        #expect(HowItWorksView.sceneFrame(elapsed: 4.2, frozen: true) == HowItWorksScene.still())
        #expect(HowItWorksView.sceneFrame(elapsed: 0.1, frozen: false).caption == "Personal saves a note")
        #expect(HowItWorksView.sceneFrame(elapsed: 3.5, frozen: false) == HowItWorksScene.frame(at: 3.5 / Theme.Motion.slow))
        // A clock that reads a hair before the appearance never shows a frame from the end of the loop.
        #expect(HowItWorksView.sceneFrame(elapsed: -0.01, frozen: false) == HowItWorksScene.frame(at: 0))
    }

    static func render(_ view: some View) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    /// How many pixels of `small` differ by more than a trace from `large` at a pixel offset (every pixel counts when
    /// `small` does not fit there).
    static func differing(_ large: NSBitmapImageRep, _ small: NSBitmapImageRep, at offset: CGPoint) -> Int {
        let ox = Int(offset.x), oy = Int(offset.y)
        guard ox >= 0, oy >= 0, ox + small.pixelsWide <= large.pixelsWide, oy + small.pixelsHigh <= large.pixelsHigh,
              let pl = large.bitmapData, let ps = small.bitmapData else { return .max }
        var count = 0
        for y in 0..<small.pixelsHigh {
            for x in 0..<small.pixelsWide {
                let i = (y + oy) * large.bytesPerRow + (x + ox) * large.bitsPerPixel / 8, j = y * small.bytesPerRow + x * small.bitsPerPixel / 8
                if (0..<4).contains(where: { abs(Int(pl[i + $0]) - Int(ps[j + $0])) > 24 }) { count += 1 }
            }
            if count > 5000 { return count }
        }
        return count
    }

    /// How many pixels differ by more than a trace between two renders of the same size.
    static func differing(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData else { return .max }
        var count = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                let i = y * a.bytesPerRow + x * a.bitsPerPixel / 8, j = y * b.bytesPerRow + x * b.bitsPerPixel / 8
                if (0..<4).contains(where: { abs(Int(pa[i + $0]) - Int(pb[j + $0])) > 8 }) { count += 1 }
            }
        }
        return count
    }

    /// The names, labels and captions are laid out once and drawn from the cache on every later frame, the same way.
    @Test func textIsResolvedOnceAndDrawnTheSame() throws {
        let typing = HowItWorksScene.frame(at: 0.3), copies = HowItWorksScene.frame(at: 2.0)
        let texts = HowItWorksTexts()
        _ = try #require(Self.render(HowItWorksCanvas(frame: typing, texts: texts)))
        let resolved = texts.resolutions
        #expect(resolved == 7)   // 3 names, "Memory", "on this Mac", the prompt and one caption
        let cached = try #require(Self.render(HowItWorksCanvas(frame: typing, texts: texts)))
        #expect(texts.resolutions == resolved)
        _ = Self.render(HowItWorksCanvas(frame: copies, texts: texts))
        #expect(texts.resolutions == resolved + 1)   // only the second half of the caption is new
        // Drawn from the cache, the frame matches one laid out afresh: a cold first layout may rasterize a few hundred edge
        // pixels differently, while the caption alone covers about 1,900.
        let fresh = try #require(Self.render(HowItWorksCanvas(frame: typing, texts: HowItWorksTexts())))
        var unsaid = typing
        unsaid.captionOpacity = 0
        let withoutCaption = try #require(Self.render(HowItWorksCanvas(frame: unsaid, texts: texts)))
        #expect(Self.differing(cached, fresh) < 800)
        #expect(Self.differing(cached, withoutCaption) > 800)
    }
}
