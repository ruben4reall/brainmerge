import SwiftUI
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct ThemeTests {
    @Test func everyTintHasAHexFromTheDesignNote() {
        let expected: [Tint: String] = [.orange: "#D97757", .blue: "#6FA3D8", .green: "#7FA37A", .purple: "#A87BC9",
                                        .pink: "#D97A8E", .red: "#D97A8E", .yellow: "#E0A526", .gray: "#7D8A99"]
        for tint in Tint.allCases { #expect(Theme.hex(for: tint) == expected[tint]) }
        #expect(Theme.auraColors.count == 6)
    }
    @Test func soberTokens() {
        // Claude-style visual identity: subtle halos, soft aura, a single accent (the creature's purple).
        #expect(Theme.Halo.opacity <= 0.2)
        #expect(Theme.Halo.radius >= 90)
        #expect(Theme.Aura.softOpacity <= 0.15 && Theme.Aura.fullOpacity <= 0.6)
        #expect(Theme.Aura.lineWidth <= 10)
        #expect(Theme.Creature.glowOpacity <= 0.35)
        // The accent is the creature's purple.
        let (r, g, b) = Theme.Colors.accent.rgb255
        #expect((r, g, b) == (160, 107, 224))
        #expect(Theme.Colors.creature.rgb255 == Theme.Colors.accent.rgb255)
        // Sidebar rows: hover and press are neutral cream, fainter than the purple selection, which keeps meaning "selected".
        func alpha(_ c: Color) -> CGFloat { NSColor(c).usingColorSpace(.sRGB)?.alphaComponent ?? 1 }
        #expect(Theme.Colors.rowHover.rgb255 == Theme.Colors.text.rgb255)
        #expect(Theme.Colors.rowPressed.rgb255 == Theme.Colors.text.rgb255)
        #expect(Theme.Colors.rowHover.rgb255 != Theme.Colors.accent.rgb255)
        #expect(alpha(Theme.Colors.rowHover) > 0 && alpha(Theme.Colors.rowHover) <= 0.08)
        #expect(alpha(Theme.Colors.rowHover) < alpha(Theme.Colors.rowPressed))
        #expect(alpha(Theme.Colors.rowPressed) < alpha(Theme.Colors.selection))
        #expect(Theme.Layout.rowRadius == 10)
        // The launch: a short splash that never holds a fast launch back, a calm stepped walk, a quick crossfade.
        #expect(Theme.Launch.minimumVisible <= .milliseconds(500))
        #expect((0.08...0.2).contains(Theme.Launch.frameDuration))
        #expect(Theme.Launch.fade <= 0.3)
        #expect(Theme.Launch.reducedFade < Theme.Launch.fade)
        #expect(Theme.Launch.slowCaptionAfter >= 1)
        #expect(Theme.Launch.unit == Theme.Launch.unit.rounded())
    }

    @Test func pickableTintsShowEachColorOnce() {
        let hexes = Theme.pickableTints.map(Theme.hex(for:))
        #expect(Set(hexes).count == hexes.count)
        #expect(Theme.pickableTints.contains(.pink) && !Theme.pickableTints.contains(.red))
    }
    @Test func hexColorsRoundTrip() {
        let c = Color(hex: "#D97757")
        let (r, g, b) = c.rgb255
        #expect(r == 217 && g == 119 && b == 87)
    }
    @Test func orbInitials() {
        #expect(OrbView.initial(for: "ClientStudio") == "C")
        #expect(OrbView.initial(for: "  élodie ") == "É")
        #expect(OrbView.initial(for: "") == "?")
        #expect(OrbView.initial(for: "42 tests") == "4")
    }

    /// WCAG contrast of a (possibly translucent) foreground over an opaque background.
    static func contrast(_ foreground: Color, over background: Color) -> Double {
        func linear(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let fg = NSColor(foreground).usingColorSpace(.sRGB)!, bg = NSColor(background).usingColorSpace(.sRGB)!
        let a = fg.alphaComponent
        func blend(_ f: CGFloat, _ b: CGFloat) -> CGFloat { f * a + b * (1 - a) }
        let r = blend(fg.redComponent, bg.redComponent), g = blend(fg.greenComponent, bg.greenComponent), b = blend(fg.blueComponent, bg.blueComponent)
        let l1 = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        let l2 = 0.2126 * linear(bg.redComponent) + 0.7152 * linear(bg.greenComponent) + 0.0722 * linear(bg.blueComponent)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test func faintTextAndButtonLabelsMeetAA() {
        // Small text needs 4.5:1 (WCAG AA): the faint labels on the canvas, the white label on a purple button.
        #expect(Self.contrast(Theme.Colors.textFaint, over: Theme.Colors.background) >= 4.5)
        #expect(Self.contrast(Theme.Colors.textMuted, over: Theme.Colors.background) >= 4.5)
        #expect(Self.contrast(Theme.Colors.onAccent, over: Theme.Colors.button) >= 4.5)
    }

    @Test func noHardCodedColorsOutsideTheme() throws {
        // Everything visible flows through Theme.swift: a hex or a bare white outside it is a retheming trap.
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "Theme.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Color(hex:") || line.contains("Color.white") || line.contains("Color.black") {
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
