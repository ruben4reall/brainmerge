import SwiftUI
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct ThemeTests {
    @Test func everyTintHasAHexFromTheDesignNote() {
        let expected: [Tint: String] = [.orange: "#D97757", .blue: "#6FA3D8", .green: "#7FA37A", .purple: "#A87BC9",
                                        .pink: "#D97A8E", .red: "#D97A8E", .yellow: "#E0A526", .gray: "#7D8A99"]
        for tint in Tint.allCases { #expect(Theme.hex(for: tint) == expected[tint]) }
    }
    @Test func soberTokens() {
        // A single accent: the creature's purple.
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

    /// The launch's beat: assemble, then leap home. The hand-off never waits longer than today's 0.48 s.
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

    /// Reduce Motion means opacity and color only: what moves or resizes the layout gets no animation at all (the layout
    /// changes at once), while a color or an opacity keeps a 0.15 s fade.
    @Test func reduceMotionDropsLayoutAnimations() {
        #expect(Theme.Motion.layout(Theme.Motion.settle, true) == nil)
        #expect(Theme.Motion.layout(Theme.Motion.settle, false) == Theme.Motion.settle)
        #expect(Theme.Motion.unlessReduced(Theme.Motion.settle, true) == Theme.Motion.reduced)
    }

    /// Every animation keyed on something that moves or resizes the layout (a card added, a line or a block that drops
    /// in, a spinner before a sentence, a sheet that grows) is dropped under Reduce Motion, never swapped for the 0.15 s
    /// linear fade, which would still slide the layout; what appears fades in place by its own transition.
    @Test func reduceMotionNeverSlidesTheLayout() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI")
        let layoutKeys: [(String, String)] = [
            ("Screens/AccountsView.swift", "query.isEmpty ? shown.map(\\.id) : []"), ("Screens/AccountsView.swift", "button.label"),
            ("Design/ScreenHeader.swift", "busy"),
            ("Screens/ConnectionsSection.swift", "options.isEmpty"), ("Screens/ConnectionsSection.swift", "choice"),
            ("Screens/ConnectionsSection.swift", "serversRead"), ("Screens/ConnectionsSection.swift", "showsServers"),
            ("Screens/AddAccountSheet.swift", "advanced"), ("Screens/EditAccountSheet.swift", "swapProblem?.id"),
            ("Screens/UsageView.swift", "state"), ("Screens/UsageView.swift", "placeholder"),
            ("Screens/UsageView.swift", "days.map(\\.output)"), ("Screens/UsageView.swift", "output"), ("Screens/UsageView.swift", "total"),
            ("Design/StateMotion.swift", "key ?? text"), ("Screens/MemoryGraphView.swift", "recent"),
            ("Screens/MemoryGraphView.swift", "counts"), ("Screens/MemoryGraphView.swift", "ordered.map(\\.id)"),
            ("Screens/ResourcesSection.swift", "text"),
            ("Screens/StateProblemView.swift", "model.canRestorePreviousState"),
            ("Screens/SettingsView.swift", "model.commandLineInstalled"), ("Screens/SettingsView.swift", "sentence"),
            ("Screens/SettingsView.swift", "model.hooks?.sentence"), ("Screens/ResourcesSection.swift", "model.diskMeasuring"),
            ("Screens/RootView.swift", "account.isRunning"),
            ("Screens/OnboardingView.swift", "added.isRunning"), ("Screens/OnboardingView.swift", "added.needsLogin"),
            ("Screens/OnboardingView.swift", "model.addedSlug"), ("Screens/OnboardingView.swift", "card"),
        ]
        var offenders: [String] = []
        for (file, key) in layoutKeys {
            let source = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            let animations = Self.animations(in: source).filter { $0.key == key }
            if animations.isEmpty { offenders.append("\(file): nothing animates on \(key)") }
            for animation in animations where !(animation.argument.contains("Theme.Motion.layout(") || animation.argument.hasPrefix("reduceMotion ? nil")) {
                offenders.append("\(file): \(key) eases the layout under Reduce Motion (\(animation.argument))")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
        // The header's words swap in order (`SwappingText`, keyed on the words without their RAM figure), inside the busy
        // animation: the spinner arriving with a new sentence pushes it aside at once under Reduce Motion.
        let header = try String(contentsOf: sources.appending(path: "Design/ScreenHeader.swift"), encoding: .utf8)
        #expect(header.contains("SwappingText(text: subtitle, key: changeKey)"))
        let words = try #require(header.range(of: "SwappingText(")), busy = try #require(header.range(of: "value: busy)"))
        #expect(words.lowerBound < busy.lowerBound)
    }

    /// Each `.animation(argument, value: key)` of a source, whitespace folded.
    static func animations(in source: String) -> [(argument: String, key: String)] {
        let folded = source.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return folded.components(separatedBy: ".animation(").dropFirst().compactMap { chunk in
            guard let value = chunk.range(of: ", value: ") else { return nil }
            let argument = String(chunk[..<value.lowerBound])
            var depth = 0, key = ""
            for c in chunk[value.upperBound...] {
                if c == "(" { depth += 1 } else if c == ")" { if depth == 0 { break }; depth -= 1 }
                key.append(c)
            }
            // An argument with an unbalanced parenthesis is not one `.animation(_:value:)` call.
            guard argument.filter({ $0 == "(" }).count == argument.filter({ $0 == ")" }).count else { return nil }
            return (argument, key)
        }
    }

    /// The six-color aura, the background halos and the unused pill button are gone for good: an opening account gets
    /// a stroke in its own color, the canvas stays quiet. Nothing may bring them back by a token change.
    @Test func noAuraHaloOrDeadButtonStyleLeft() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for word in ["AuraView", "AuraState", "auraColors", "enum Aura", "enum Halo", "Theme.Halo", "AccentPillButtonStyle", "accents:"]
            where text.contains(word) { offenders.append("\(url.lastPathComponent): \(word)") }
        }
        #expect(offenders.isEmpty, "\(offenders)")
        #expect(!FileManager.default.fileExists(atPath: sources.appending(path: "Design/AuraView.swift").path))
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

    /// A setting that turns on or off is a switch in the accent (DESIGN.md rule 3), never the system's blue checkbox.
    @Test func everySettingToggleIsAnAccentSwitch() throws {
        let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        for name in ["SettingsView.swift", "EditAccountSheet.swift", "OnboardingView.swift", "AddAccountSheet.swift"] {
            let lines = try String(contentsOf: screens.appending(path: name), encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("Toggle(") {
                // The toggle and the modifier lines that follow it.
                var statement = String(line)
                for next in lines.dropFirst(index + 1) {
                    guard next.trimmingCharacters(in: .whitespaces).hasPrefix(".") else { break }
                    statement += next
                }
                #expect(statement.contains(".toggleStyle(.switch)") && statement.contains(".tint(Theme.Colors.accent)"), "\(name):\(index + 1)")
            }
        }
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
