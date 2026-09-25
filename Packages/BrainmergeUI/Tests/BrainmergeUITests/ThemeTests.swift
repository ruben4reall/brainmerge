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
        // The launch: a short splash that never holds a fast launch back, a calm stepped walk, a quick fade of the screens.
        #expect(Theme.Launch.minimumVisible <= .milliseconds(500))
        #expect((0.08...0.2).contains(Theme.Launch.frameDuration))
        #expect(Theme.Launch.fade <= 0.3)
        #expect(Theme.Launch.reducedFade < Theme.Launch.fade)
        #expect(Theme.Launch.slowCaptionAfter >= 1)
        #expect(Theme.Launch.unit == Theme.Launch.unit.rounded())
    }

    /// The launch's beat: assemble, then leap home. The app never waits longer than today's 0.48 s for it.
    @Test func launchTokensPinTheBeat() {
        #expect(Theme.Launch.unit == 7 && Theme.Launch.frameDuration == 0.12 && Theme.Launch.lift == 20)
        #expect(Theme.Launch.minimumVisible == .milliseconds(480))
        #expect(Theme.Launch.fade == 0.30 && Theme.Launch.reducedFade == 0.15)
        #expect(Theme.Launch.slowCaptionAfter == 2.0)
        #expect(Theme.Launch.leap == 0.50 && Theme.Launch.leapApex == 12 && Theme.Launch.anticipation == 0.08)
        #expect(Theme.Launch.gatherSpread == 2.4 && Theme.Launch.heroTime == 1.46)
        // The scene reads its numbers from the tokens.
        #expect(AssembleScene.heroTime == Theme.Launch.heroTime && AssembleScene.unit == Theme.Launch.unit)
        #expect(AssembleScene.minimumVisible == 0.48 && LaunchDirector.walkFrame == Theme.Launch.frameDuration)
        #expect(Leap.flight == Theme.Launch.leap && Leap.apex == Theme.Launch.leapApex && Leap.anticipation == Theme.Launch.anticipation)
        // The hero still comes after the beat's last blink and before the walk.
        #expect(Theme.Launch.heroTime < AssembleScene.idleStart && Theme.Launch.anticipation < Theme.Launch.leap)
    }

    /// Motion: interface changes stay quick, a page a little longer, Reduce Motion's fade shorter than any of them.
    @Test func motionTokensStayQuick() {
        for d in [Theme.Motion.hover, Theme.Motion.quick, Theme.Motion.base] { #expect(d > 0 && d <= 0.25) }
        #expect(Theme.Motion.hover < Theme.Motion.quick && Theme.Motion.quick < Theme.Motion.base)
        #expect(Theme.Motion.page <= 0.35 && Theme.Motion.page > Theme.Motion.base)
        #expect(Theme.Motion.reducedDuration < Theme.Motion.base)
        #expect(Theme.Motion.ring == 1.2)
        // Tests are never a capture, and never slowed down.
        #expect(!Theme.Motion.isCapture)
        #expect(Theme.Motion.slow == 1)
        #expect(Theme.Motion.slowFactor(environment: [:], debug: true) == 1)
        #expect(Theme.Motion.slowFactor(environment: ["BRAINMERGE_SLOW_MOTION": "4"], debug: true) == 4)
        #expect(Theme.Motion.slowFactor(environment: ["BRAINMERGE_SLOW_MOTION": "4"], debug: false) == 1)
        #expect(Theme.Motion.slowFactor(environment: ["BRAINMERGE_SLOW_MOTION": "zero"], debug: true) == 1)
        #expect(Theme.Motion.slowFactor(environment: ["BRAINMERGE_SLOW_MOTION": "0.1"], debug: true) == 1)
        #expect(Theme.Motion.isCapture(environment: ["BRAINMERGE_CAPTURE": "1"]))
        #expect(!Theme.Motion.isCapture(environment: ["BRAINMERGE_HOME": "/tmp/demo"]))
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
    @MainActor @Test func orbInitials() {
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

    /// The RAM bars of the Usage screen: neutral cream (the purple means an action, a tint means an account), a thin
    /// bar still visible on the canvas (3:1, the bar for graphics), on the same track as the fields.
    @Test func ramBarsAreNeutralAndVisible() {
        func alpha(_ c: Color) -> CGFloat { NSColor(c).usingColorSpace(.sRGB)?.alphaComponent ?? 1 }
        #expect(Theme.Colors.meter.rgb255 == Theme.Colors.text.rgb255)
        #expect(Self.contrast(Theme.Colors.meter, over: Theme.Colors.background) >= 3)
        #expect(alpha(Theme.Colors.meter) < alpha(Theme.Colors.textFaint))
        #expect(Theme.Layout.meterRadius > 0 && Theme.Layout.meterRadius < Theme.Layout.rowRadius)
    }

    /// A vault's graph wears Obsidian's colors under the Minimal theme in dark mode: a flat #262626 background, #999999
    /// nodes, #3F3F3F lines, #D1D1D1 labels, the accent's two shades on hover. Group colors come from the vault's file.
    @Test func aVaultWearsObsidiansColors() {
        #expect(Theme.Colors.vaultBackground.rgb255 == (0x26, 0x26, 0x26))
        #expect(Theme.Colors.vaultNode.rgb255 == (0x99, 0x99, 0x99))
        #expect(Theme.Colors.vaultLine.rgb255 == (0x3F, 0x3F, 0x3F))
        #expect(Theme.Colors.vaultText.rgb255 == (0xD1, 0xD1, 0xD1))
        #expect(Theme.Colors.vaultHighlight.rgb255 == (0x75, 0x0F, 0x0F))
        #expect(Theme.Colors.vaultFocused.rgb255 == (0x8C, 0x12, 0x12))
        #expect(Self.contrast(Theme.Colors.vaultText, over: Theme.Colors.vaultBackground) >= 4.5)
        let teal = Theme.color(group: ObsidianGraphSettings.GroupColor(rgb: 1419967, alpha: 1))
        #expect(teal.rgb255 == (21, 170, 191))
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

    /// One purple button per screen: a tint on a whole window or sheet turns every secondary glass button purple too
    /// (it happened in 0.4.0). Controls that want the accent carry their own tint.
    @Test func noWindowWideTint() throws {
        let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        for name in ["RootView.swift", "OnboardingView.swift", "EditAccountSheet.swift", "AddAccountSheet.swift"] {
            let source = try String(contentsOf: screens.appending(path: name), encoding: .utf8)
            let lines = source.split(separator: "\n").filter { $0.hasPrefix("        .tint(") }
            #expect(lines.isEmpty, "\(name) tints a whole view: \(lines)")
        }
    }
}
