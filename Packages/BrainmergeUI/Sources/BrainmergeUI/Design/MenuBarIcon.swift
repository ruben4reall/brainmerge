import AppKit
import SwiftUI
import BrainmergeCore

/// The menu bar icon: the sidebar's creature as a template image, drawn from Creature's grid (never a second grid in
/// CreatureView.swift: scripts/make-brand.swift reads the only one there). Monochrome, no badge, no animation; its eyes
/// open while an account is open. Also the colored dots of the menu's accounts.
public enum MenuBarIcon {
    /// Status items center their image: 24 by 18 points leaves the creature room and whole pixels.
    public static let canvas = CGSize(width: 24, height: 18)
    /// 1.5 points per cell: the creature is 16.5 points tall, like the menu bar's own symbols.
    static let retinaUnit: CGFloat = 1.5

    public struct Geometry: Equatable, Sendable {
        public var body: [CGRect]
        /// The eyes, cut out of the body.
        public var holes: [CGRect]
    }

    /// A cell spans whole device pixels or its edges blur: 3 pixels at 2x, 1 point at 1x (smaller, but sharp).
    public static func unit(backingScale: CGFloat) -> CGFloat {
        let scale = max(1, backingScale)
        return max(1, (retinaUnit * scale).rounded(.down)) / scale
    }

    /// The cells in a flipped canvas (y down, like the grid), centered and snapped to the display's pixels.
    public static func geometry(awake: Bool, backingScale: CGFloat) -> Geometry {
        let scale = max(1, backingScale)
        let unit = unit(backingScale: scale)
        func snapped(_ value: CGFloat) -> CGFloat { (value * scale).rounded(.down) / scale }
        let x0 = snapped((canvas.width - CGFloat(Creature.columns) * unit) / 2)
        let y0 = snapped((canvas.height - CGFloat(Creature.rows) * unit) / 2)
        let body = Creature.bodyPixels().map { CGRect(x: x0 + CGFloat($0.x) * unit, y: y0 + CGFloat($0.y) * unit, width: unit, height: unit) }
        let holes = Creature.eyes(for: awake ? .awake : .asleep).map { eye in
            // A closed eye is a line: thinner than a cell, never thinner than one pixel.
            let height = min(unit, max(1 / scale, (unit * eye.height * scale).rounded() / scale))
            return CGRect(x: x0 + CGFloat(eye.x) * unit, y: y0 + CGFloat(eye.y) * unit, width: unit, height: height)
        }
        return Geometry(body: body, holes: holes)
    }

    @MainActor private static var images: [Bool: NSImage] = [:]
    @MainActor private static var dots: [Tint: NSImage] = [:]

    /// One image per state, drawn again by AppKit at each display's scale.
    @MainActor public static func image(awake: Bool) -> NSImage {
        if let cached = images[awake] { return cached }
        let image = NSImage(size: canvas, flipped: true) { _ in
            let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) } ?? 2
            let geometry = geometry(awake: awake, backingScale: scale)
            // One even-odd path: the body without seams between cells, the eyes as holes.
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            for rect in geometry.body + geometry.holes { path.appendRect(rect) }
            // A template only keeps the alpha: macOS paints it in the menu bar's color, light or dark.
            NSColor.labelColor.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Brainmerge"
        images[awake] = image
        return image
    }

    /// An account's color in the menu: not a template, so macOS keeps the color.
    @MainActor public static func dot(_ tint: Tint) -> NSImage {
        if let cached = dots[tint] { return cached }
        let color = NSColor(Theme.color(for: tint))
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        dots[tint] = image
        return image
    }
}
