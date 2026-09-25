import SwiftUI
import BrainmergeCore

/// Design tokens for the visual identity. Everything visible in Brainmerge flows through here:
/// to re-theme the app, changing these values is enough. Guide and palette: docs/brand/DESIGN.md.
///
/// Principles: a dark, neutral background, cream text, a single accent (the creature's purple),
/// system glass surfaces, soft account colors, and subtle halos and aura.
public enum Theme {
    public enum Colors {
        // Background: dark, neutral, a touch of purple at the top left.
        public static let background = Color(hex: "#1A1918")
        public static let backgroundTop = Color(hex: "#2B2633")
        public static let backgroundBottom = Color(hex: "#151417")

        // Cream text, three levels.
        public static let text = Color(hex: "#F4EFE6")
        public static let textMuted = Color(hex: "#F4EFE6").opacity(0.64)
        public static let textFaint = Color(hex: "#F4EFE6").opacity(0.50)
        public static let surfaceLine = Color.white.opacity(0.12)

        // The single accent: the creature's purple. Action buttons, toggles, selection.
        public static let accent = Color(hex: "#A06BE0")
        public static let accentLight = Color(hex: "#B487EA")
        public static let accentDeep = Color(hex: "#8657C9")
        public static let onAccent = Color(hex: "#FBF7FF")
        /// Fill of the prominent buttons: the deep purple, so their white label reads at 4.7:1 (AA).
        public static let button = accentDeep
        /// Text fields on glass, the selected row in the sidebar, the softer accent of charts and diagrams.
        public static let field = Color.white.opacity(0.07)
        public static let selection = accent.opacity(0.18)
        public static let accentSoft = accent.opacity(0.35)
        /// Sidebar rows under the pointer and while pressed: neutral cream, fainter than `selection`,
        /// so the purple keeps meaning "selected".
        public static let rowHover = text.opacity(0.06)
        public static let rowPressed = text.opacity(0.10)
        /// The threads of the memory graph, at rest and lit by a hovered or selected note.
        public static let graphLink = Color(hex: "#F4EFE6").opacity(0.22)
        public static let graphLinkLit = Color(hex: "#F4EFE6").opacity(0.55)

        /// An Obsidian vault's graph, in the colors Obsidian gives it under the Minimal theme in dark mode (its tokens
        /// resolved: --graph-node is --text-muted, --graph-line is --color-base-35, --graph-text is --text-normal,
        /// hover is --interactive-accent and the ring --text-accent, from the accent #8B1212). Flat, like Obsidian's canvas.
        public static let vaultBackground = Color(hex: "#262626")
        public static let vaultNode = Color(hex: "#999999")
        public static let vaultLine = Color(hex: "#3F3F3F")
        public static let vaultText = Color(hex: "#D1D1D1")
        public static let vaultHighlight = Color(hex: "#750F0F")
        public static let vaultFocused = Color(hex: "#8C1212")
        /// Nodes a vault shows only when asked: attachments (Obsidian's yellow) and links to no file (--text-faint).
        public static let vaultAttachment = Color(hex: "#E0DE71")
        public static let vaultUnresolved = Color(hex: "#666666")

        /// The RAM bars of the Usage screen for what is not an account (the Mac, terminal sessions, other apps):
        /// neutral cream, on a `field` track. An account's bar takes its tint.
        public static let meter = Color(hex: "#F4EFE6").opacity(0.42)

        // States: open, saved.
        public static let sage = Color(hex: "#8FC7A6")

        // The creature (a single file, CreatureView.swift, draws it).
        public static let creature = Color(hex: "#A06BE0")
        public static let creatureEye = Color(hex: "#1E1430")
    }

    /// Blurred halos behind open accounts: present, never garish.
    public enum Halo {
        public static let opacity = 0.0      // no halo: the background stays neutral (0.14 to bring them back)
        public static let radius: CGFloat = 110
        public static let size: CGFloat = 520
    }

    /// The aura that spins during loading (Siri-style), subtle at rest.
    public enum Aura {
        public static let softOpacity = 0.10
        public static let fullOpacity = 0.45
        public static let lineWidth: CGFloat = 6
        public static let period: TimeInterval = 7
    }

    /// Motion tokens: two curves, a few durations, three springs. Scenes built from `Ease` (Motion.swift) use the same curves.
    public enum Motion {
        /// Entering, exiting, feedback: cubic-bezier(0.23, 1, 0.32, 1). Site: --ease-out.
        public static func out(_ d: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: d * slow) }
        /// Moving on screen: cubic-bezier(0.77, 0, 0.175, 1). Site: --ease-move.
        public static func inOut(_ d: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: d * slow) }
        public static let hover = 0.12, quick = 0.15, base = 0.22, page = 0.32, ring = 1.2
        public static var pop: Animation { .spring(response: 0.35 * slow, dampingFraction: 0.6) }
        public static var settle: Animation { .spring(response: 0.4 * slow, dampingFraction: 0.88) }
        public static var hop: Animation { .spring(response: 0.28 * slow, dampingFraction: 0.55) }
        /// Reduce Motion: opacity and color only, in this plain fade.
        public static let reducedDuration = 0.15
        public static let reduced = Animation.linear(duration: reducedDuration)
        /// README captures: every scene shows its still, nothing plays. `BRAINMERGE_HOME` demos stay animated.
        public static let isCapture = isCapture(environment: ProcessInfo.processInfo.environment)
        static func isCapture(environment: [String: String]) -> Bool { environment["BRAINMERGE_CAPTURE"] != nil }
        /// Debug builds only: BRAINMERGE_SLOW_MOTION=4 slows every token and every pure scene 4 times (t / slow). 1 in release.
        public static let slow: Double = {
            #if DEBUG
            slowFactor(environment: ProcessInfo.processInfo.environment, debug: true)
            #else
            1
            #endif
        }()
        static func slowFactor(environment: [String: String], debug: Bool) -> Double {
            guard debug, let text = environment["BRAINMERGE_SLOW_MOTION"], let factor = Double(text), factor >= 1, factor <= 20 else { return 1 }
            return factor
        }
    }

    /// The launch: the creature walks on the splash while the first load runs, then the window crossfades to its screen.
    public enum Launch {
        /// One pixel of the creature, in points: a whole number keeps its edges crisp.
        public static let unit: CGFloat = 7
        /// One frame of the four-frame walk (a 0.48 s step cycle, stepped like pixel art).
        public static let frameDuration: TimeInterval = 0.12
        /// The shortest the splash stays, counted from its first frame; the load's own time counts toward it.
        public static let minimumVisible: Duration = .milliseconds(480)
        /// The crossfade to the first screen, and its plain dissolve with Reduce Motion.
        public static let fade: TimeInterval = 0.25
        public static let reducedFade: TimeInterval = 0.15
        /// "Waking up…" appears only when the load takes longer than this.
        public static let slowCaptionAfter: TimeInterval = 1.5
        /// The creature sits this much above the window's center.
        public static let lift: CGFloat = 20
    }

    /// Account tints, soft and legible on the dark background. The core's red tint is rendered as pink.
    public static func hex(for tint: Tint) -> String {
        switch tint {
        case .orange: return "#D97757"
        case .blue: return "#6FA3D8"
        case .green: return "#7FA37A"
        case .purple: return "#A87BC9"
        case .pink: return "#D97A8E"
        case .red: return "#D97A8E"
        case .yellow: return "#E0A526"
        case .gray: return "#7D8A99"
        }
    }
    public static func color(for tint: Tint) -> Color { Color(hex: hex(for: tint)) }
    /// A vault's color group: the color is the vault's own, saved by Obsidian in its graph.json.
    public static func color(group: ObsidianGraphSettings.GroupColor) -> Color {
        Color(.sRGB, red: Double(group.red) / 255, green: Double(group.green) / 255, blue: Double(group.blue) / 255, opacity: group.alpha)
    }

    /// The tints offered in the app: one swatch per color (red, rendered as pink, is not repeated).
    public static let pickableTints: [Tint] = Tint.allCases.filter { hex(for: $0) != hex(for: .pink) || $0 == .pink }

    /// The aura's colors: centered on purple, with a touch of blue, green, and amber.
    public static let auraColors: [Color] = ["#A06BE0", "#C58FD9", "#7FB5E8", "#8FC7A6", "#E9A45C", "#B487EA"].map { Color(hex: $0) }

    /// Layout constants shared by the screens.
    public enum Layout {
        public static let padding: CGFloat = 20
        public static let cardRadius: CGFloat = 12
        /// The rows of the sidebar: screens and accounts, their hover, press and selection fills.
        public static let rowRadius: CGFloat = 10
        /// Reading column of the Memory and Usage screens: cards never stretch beyond it.
        public static let readingWidth: CGFloat = 880
        /// The settings form.
        public static let formWidth: CGFloat = 720
        /// The thin RAM bars of the Usage screen.
        public static let meterRadius: CGFloat = 3
    }

    public enum Fonts {
        public static let screenTitle = Font.system(size: 26, weight: .medium, design: .serif)
        public static let onboardingTitle = Font.system(size: 30, weight: .medium, design: .serif)
        public static let sheetTitle = Font.system(size: 22, weight: .medium, design: .serif)
        public static let cardName = Font.system(size: 13, weight: .semibold)
        public static let figure = Font.system(size: 22, weight: .semibold)
        public static let body = Font.system(size: 14)
        public static let secondary = Font.system(size: 12.5)
        public static let sectionLabel = Font.system(size: 11.5, weight: .semibold)
        public static let caption = Font.system(size: 11)
    }
}

public extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
    /// Components 0 to 255 (tests and icon generation).
    var rgb255: (Int, Int, Int) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
}
