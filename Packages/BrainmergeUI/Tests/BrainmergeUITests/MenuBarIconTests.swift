import AppKit
import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct MenuBarIconTests {
    func onWholePixels(_ rect: CGRect, scale: CGFloat) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { value in
            let pixels = value * scale
            return abs(pixels - pixels.rounded()) < 0.0001
        }
    }

    /// The creature of the sidebar, cell for cell from its grid, on whole device pixels so it stays sharp.
    @Test func cellsComeFromTheGridOnWholePixels() {
        #expect(MenuBarIcon.unit(backingScale: 2) == 1.5)
        #expect(MenuBarIcon.unit(backingScale: 1) == 1)
        let canvas = MenuBarIcon.canvas
        for scale in [1.0, 2.0] as [CGFloat] {
            for awake in [true, false] {
                let g = MenuBarIcon.geometry(awake: awake, backingScale: scale)
                let unit = MenuBarIcon.unit(backingScale: scale)
                #expect(g.body.count == Creature.bodyPixels().count)
                #expect(g.body.allSatisfy { $0.width == unit && $0.height == unit })
                #expect(g.holes.count == 2)
                for rect in g.body + g.holes {
                    #expect(onWholePixels(rect, scale: scale), "\(rect) at \(scale)x")
                    #expect(CGRect(origin: .zero, size: canvas).contains(rect), "\(rect) at \(scale)x")
                }
                // Mirrored left to right, like the grid.
                let mirrored = Set(g.body.map { CGRect(x: canvas.width - $0.maxX, y: $0.minY, width: $0.width, height: $0.height).debugDescription })
                #expect(mirrored == Set(g.body.map(\.debugDescription)))
                // Every eye is cut out of a body cell.
                for hole in g.holes { #expect(g.body.contains { $0.contains(hole) }, "\(hole)") }
            }
            let awake = MenuBarIcon.geometry(awake: true, backingScale: scale), asleep = MenuBarIcon.geometry(awake: false, backingScale: scale)
            let unit = MenuBarIcon.unit(backingScale: scale)
            // Open eyes are whole cells; closed ones a thin line one row lower, never thinner than a device pixel.
            #expect(awake.holes.allSatisfy { $0.width == unit && $0.height == unit })
            #expect(zip(awake.holes, asleep.holes).allSatisfy { $1.minY == $0.minY + unit && $1.minX == $0.minX })
            #expect(asleep.holes.allSatisfy { $0.height >= 1 / scale && $0.height <= unit })
            // On a Retina display a closed eye is thinner than an open one; at 1x one pixel is all there is.
            if scale == 2 { #expect(asleep.holes.allSatisfy { $0.height < unit }) }
        }
        // About 16 to 18 points tall on a Retina display.
        let retina = MenuBarIcon.geometry(awake: true, backingScale: 2)
        let height = (retina.body.map(\.maxY).max() ?? 0) - (retina.body.map(\.minY).min() ?? 0)
        #expect((16...18).contains(height))
    }

    /// A template image: macOS draws it in the menu bar's own color, light or dark, never in a color of ours.
    @MainActor @Test func theImageIsATemplateOfTheCanvasSize() {
        for awake in [true, false] {
            let image = MenuBarIcon.image(awake: awake)
            #expect(image.isTemplate)
            #expect(image.size == MenuBarIcon.canvas)
            #expect(MenuBarIcon.image(awake: awake) === image)
        }
        #expect(MenuBarIcon.image(awake: true) !== MenuBarIcon.image(awake: false))
    }

    /// Each account's dot keeps its own color in the menu: not a template, one image per color.
    @MainActor @Test func accountDotsKeepTheirColor() {
        let dot = MenuBarIcon.dot(.green)
        #expect(!dot.isTemplate)
        #expect(MenuBarIcon.dot(.green) === dot)
        #expect(MenuBarIcon.dot(.blue) !== dot)
    }
}
