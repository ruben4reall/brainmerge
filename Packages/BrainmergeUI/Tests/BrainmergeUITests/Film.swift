import AppKit
import SwiftUI
@testable import BrainmergeUI

/// A view filmed the way a window draws it, frame by frame, in a window placed off every screen (see
/// `TimelineDrawingTests.window`): what really moves, and when, as the main run loop runs. In the light appearance, on a
/// mid-gray ground, the glass is not drawn but every word is: black words darker than the ground, cream ones lighter.
@MainActor final class Film {
    /// The ground: #777777.
    nonisolated static let ground: CGFloat = 0.467
    let window: NSWindow

    /// `view` pinned to the top left of a `size` window.
    init<V: View>(_ view: V, size: CGSize) {
        let root = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(white: Self.ground))
            .environment(\.colorScheme, .light)
        window = TimelineDrawingTests.window(for: root)
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(size)
    }

    func close() { window.orderOut(nil) }

    /// Runs the main run loop (the view draws, the model's tasks go on) for `seconds`.
    func run(for seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.004))) }
    }

    /// Runs the main run loop until `done` holds, `timeout` at most; whether it held.
    @discardableResult
    func run(until done: () -> Bool, timeout: Double) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !done() {
            guard Date() < end else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
        }
        return true
    }

    /// Films from now for `seconds`, one shot every few milliseconds, each with its time from now.
    func shots(for seconds: Double) -> [(time: Double, shot: Shot)] {
        let start = Date()
        var shots: [(time: Double, shot: Shot)] = []
        while Date().timeIntervalSince(start) < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
            shots.append((Date().timeIntervalSince(start), shot()))
        }
        return shots
    }

    /// What the window shows now.
    func shot() -> Shot {
        let view = window.contentView!
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return Shot(rep: rep)
    }

    /// One frame: its pixels read as luminance, 0 black to 1 white, (0, 0) at the top left.
    struct Shot {
        let rep: NSBitmapImageRep
        var width: Int { rep.pixelsWide }
        var height: Int { rep.pixelsHigh }
        /// Pixels per point.
        var scale: CGFloat { CGFloat(rep.pixelsWide) / rep.size.width }

        func luma(_ x: Int, _ y: Int) -> CGFloat {
            if rep.bitsPerSample == 8, !rep.isPlanar, let data = rep.bitmapData, rep.samplesPerPixel >= 3 {
                let first = rep.hasAlpha && rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
                let pixel = data + y * rep.bytesPerRow + x * (rep.bitsPerPixel / 8) + first
                return (0.299 * CGFloat(pixel[0]) + 0.587 * CGFloat(pixel[1]) + 0.114 * CGFloat(pixel[2])) / 255
            }
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return Film.ground }
            return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        }

        /// How much darker than the ground: a black word at full strength is about 0.45.
        func dark(_ x: Int, _ y: Int) -> CGFloat { max(0, Film.ground - luma(x, y)) }
        /// How much lighter than the ground: a cream word at full strength is about 0.45, a muted one about 0.3.
        func light(_ x: Int, _ y: Int) -> CGFloat { max(0, luma(x, y) - Film.ground) }
        func ink(_ tone: Tone, _ x: Int, _ y: Int) -> CGFloat { tone == .dark ? dark(x, y) : light(x, y) }

        /// The pixels of `rect` in `tone` by more than `threshold`.
        func count(_ tone: Tone, in rect: PixelRect, threshold: CGFloat) -> Int {
            var count = 0
            for y in rect.rows(in: self) { for x in rect.columns(in: self) where ink(tone, x, y) > threshold { count += 1 } }
            return count
        }

        /// The rows of `rect` (pixels) holding a pixel darker than the ground by more than `threshold`.
        func darkRows(in rect: PixelRect, threshold: CGFloat = 0.2) -> [Int] {
            rect.rows(in: self).filter { y in rect.columns(in: self).contains { x in dark(x, y) > threshold } }
        }

        /// The total darkness of `rect`: a word fading out goes toward 0.
        func darkness(in rect: PixelRect) -> CGFloat {
            var sum: CGFloat = 0
            for y in rect.rows(in: self) { for x in rect.columns(in: self) { sum += dark(x, y) } }
            return sum
        }

        /// The pixels of `rect` that are dark (black words) in one shot and not in the other.
        func differingDark(from other: Shot, in rect: PixelRect, threshold: CGFloat = 0.2) -> Int {
            var count = 0
            for y in rect.rows(in: self) {
                for x in rect.columns(in: self) where (dark(x, y) > threshold) != (other.dark(x, y) > threshold) { count += 1 }
            }
            return count
        }

        /// The black lines of the shot, from the top: runs of rows with dark pixels, split where `gap` rows hold none.
        func darkLines(in rect: PixelRect? = nil, threshold: CGFloat = 0.2, gap: Int = 4) -> [PixelRect] {
            lines(.dark, in: rect, threshold: threshold, gap: gap)
        }

        /// The lines of words in `tone`, from the top: runs of rows with such pixels, split where `gap` rows hold none.
        func lines(_ tone: Tone, in rect: PixelRect? = nil, threshold: CGFloat = 0.2, gap: Int = 4) -> [PixelRect] {
            let area = rect ?? PixelRect(x: 0, y: 0, width: width, height: height)
            var lines: [PixelRect] = []
            var top: Int?, last = 0
            for y in area.rows(in: self) {
                let inked = area.columns(in: self).contains { ink(tone, $0, y) > threshold }
                if inked {
                    if top == nil { top = y }
                    last = y
                } else if let t = top, y - last > gap {
                    lines.append(PixelRect(x: area.x, y: t, width: area.width, height: last - t + 1))
                    top = nil
                }
            }
            if let t = top { lines.append(PixelRect(x: area.x, y: t, width: area.width, height: last - t + 1)) }
            return lines
        }

        /// The words of a line: runs of columns with dark pixels, split where `gap` columns hold none.
        func darkWords(in line: PixelRect, threshold: CGFloat = 0.2, gap: Int) -> [PixelRect] {
            words(.dark, in: line, threshold: threshold, gap: gap)
        }

        /// The words of a line in `tone`: runs of columns with such pixels, split where `gap` columns hold none.
        func words(_ tone: Tone, in line: PixelRect, threshold: CGFloat = 0.2, gap: Int) -> [PixelRect] {
            var words: [PixelRect] = []
            var left: Int?, last = 0
            for x in line.columns(in: self) {
                let inked = line.rows(in: self).contains { ink(tone, x, $0) > threshold }
                if inked {
                    if left == nil { left = x }
                    last = x
                } else if let l = left, x - last > gap {
                    words.append(PixelRect(x: l, y: line.y, width: last - l + 1, height: line.height))
                    left = nil
                }
            }
            if let l = left { words.append(PixelRect(x: l, y: line.y, width: last - l + 1, height: line.height)) }
            return words
        }
    }

    /// Black words, darker than the ground, or cream ones, lighter.
    enum Tone { case dark, light }

    /// A rectangle of pixels; clipped to the shot wherever it is read.
    struct PixelRect: Equatable, CustomStringConvertible {
        var x: Int, y: Int, width: Int, height: Int
        func rows(in shot: Shot) -> Range<Int> { max(0, y)..<max(max(0, y), min(shot.height, y + height)) }
        func columns(in shot: Shot) -> Range<Int> { max(0, x)..<max(max(0, x), min(shot.width, x + width)) }
        func grown(top: Int = 0, bottom: Int = 0, sides: Int = 0) -> PixelRect {
            PixelRect(x: x - sides, y: y - top, width: width + 2 * sides, height: height + top + bottom)
        }
        var description: String { "(\(x), \(y), \(width)×\(height) px)" }
    }
}
