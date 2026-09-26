import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BrainmergeUI

/// The Memory graph's status capsule, filmed as it goes from "Live" to "Changed just now" and back.
@MainActor @Suite struct GraphStatusTests {
    @MainActor @Observable final class Status { var recent = false; var change: Date? }

    /// The capsule alone, drawn again as its status changes.
    struct Capsule: View {
        let status: Status
        var body: some View {
            GraphStatusLine(recent: status.recent, change: status.change, counts: "16 notes · 4 projects · 28 links").padding(20)
        }
    }

    /// Where the words start: past the page's padding, the capsule's own, the dot and its ring.
    static let wordsFrom: CGFloat = 20 + 10 + 6 + 6

    /// The capsule's line of words in a shot at rest, grown by a swapped word's lift.
    static func line(_ shot: Film.Shot) -> Film.PixelRect? {
        let s = shot.scale, x = Int(wordsFrom * s)
        let area = Film.PixelRect(x: x, y: 0, width: shot.width - x, height: shot.height)
        return shot.lines(.light, in: area).first.map { $0.grown(top: Int((SwapText.lift + 1) * s), bottom: Int((SwapText.lift + 1) * s)) }
    }

    /// The spaces between the counts' words at rest, as columns counted back from their right end, each narrowed by 2 pixels
    /// on both sides (a glyph's soft edge, a position between two pixels); `status` is how many words come before them.
    static func spaces(_ shot: Film.Shot, in line: Film.PixelRect, status: Int) -> [ClosedRange<Int>] {
        let words = shot.words(.light, in: line, threshold: 0.05, gap: Int(2 * shot.scale))
        guard let end = words.last.map({ $0.x + $0.width - 1 }), words.count > status + 1 else { return [] }
        let counts = Array(words.dropFirst(status))
        return zip(counts, counts.dropFirst()).compactMap { left, right in
            let from = end - (right.x - 3), to = end - (left.x + left.width + 2)
            return from <= to ? from...to : nil
        }
    }

    /// The right end of the words in a shot: the counts' last letter.
    static func end(_ shot: Film.Shot, in line: Film.PixelRect) -> Int? {
        line.columns(in: shot).last { x in line.rows(in: shot).contains { shot.light(x, $0) > 0.05 } }
    }

    /// The strongest word ink in the counts' spaces, placed from their right end in `shot`.
    static func inkInSpaces(_ shot: Film.Shot, in line: Film.PixelRect, spaces: [ClosedRange<Int>]) -> CGFloat {
        guard let end = end(shot, in: line) else { return 0 }
        var ink: CGFloat = 0
        for space in spaces {
            for x in (end - space.upperBound)...(end - space.lowerBound) {
                for y in line.rows(in: shot) { ink = max(ink, shot.light(x, y)) }
            }
        }
        return ink
    }

    /// The counts move with the capsule's new width, but never over a word: in every frame of the swap, both ways, the
    /// spaces between the counts' words stay empty. The status and its counts were one text rolling as numbers: the counts
    /// slid left at full strength across "Changed just now" while it still faded (and right across it as it came).
    @Test(.needsARealDisplay) func theCountsNeverSlideAcrossTheWords() throws {
        let status = Status()
        let film = Film(Capsule(status: status), size: CGSize(width: 480, height: 70))
        defer { film.close() }
        film.run(for: 0.4)
        let live = film.shot()
        let line = try #require(Self.line(live), "no words drawn")
        let spaces = Self.spaces(live, in: line, status: 1)
        #expect(spaces.count >= 6, "the counts' spaces: \(spaces)")
        let liveEnd = try #require(Self.end(live, in: line))
        #expect(Self.inkInSpaces(live, in: line, spaces: spaces) < 0.05, "at rest, the spaces hold ink")

        status.change = Date(); status.recent = true
        for (time, shot) in film.shots(for: 0.5) {
            let ink = Self.inkInSpaces(shot, in: line, spaces: spaces)
            #expect(ink < 0.05, "to Changed just now, \(Int(time * 1000)) ms: words under the counts (\(ink))")
        }
        let changedEnd = try #require(Self.end(film.shot(), in: line))
        #expect(changedEnd - liveEnd > Int(40 * live.scale), "the counts never moved: \(liveEnd) to \(changedEnd)")

        status.recent = false
        for (time, shot) in film.shots(for: 0.5) {
            let ink = Self.inkInSpaces(shot, in: line, spaces: spaces)
            #expect(ink < 0.05, "back to Live, \(Int(time * 1000)) ms: words under the counts (\(ink))")
        }
        #expect(Self.end(film.shot(), in: line).map { abs($0 - liveEnd) <= 1 } == true, "the counts are not back in place")
    }
}
