import Foundation

/// A vault's graph settings as Obsidian keeps them: `.obsidian/graph.json` (filters, color groups, display, forces,
/// zoom) and the Excluded files of `.obsidian/app.json`. Missing or unreadable values take Obsidian's own defaults,
/// one value at a time, and values beyond Obsidian's sliders are brought back inside them. Only these two files are
/// read, never written.
public struct ObsidianGraphSettings: Equatable, Sendable {
    /// A color stored the way graph.json stores it: one integer for the three bytes, and an opacity.
    public struct GroupColor: Equatable, Hashable, Sendable {
        public let rgb: Int
        public let alpha: Double
        public init(rgb: Int, alpha: Double) { self.rgb = min(max(rgb, 0), 0xFFFFFF); self.alpha = min(max(alpha, 0), 1) }
        public var red: Int { (rgb >> 16) & 0xFF }
        public var green: Int { (rgb >> 8) & 0xFF }
        public var blue: Int { rgb & 0xFF }
        public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    }

    public struct ColorGroup: Equatable, Sendable {
        public var query: String
        public var color: GroupColor
        public init(query: String, color: GroupColor) { self.query = query; self.color = color }
    }

    // Filters
    public var search = ""
    public var showAttachments = false
    public var hideUnresolved = false
    public var showOrphans = true
    /// Groups in order: a file takes the color of the first one it matches.
    public var colorGroups: [ColorGroup] = []
    /// app.json's Excluded files: path prefixes, or regular expressions between slashes.
    public var ignoreFilters: [String] = []
    // Display
    public var showArrow = false
    public var textFadeMultiplier = 0.0
    public var nodeSizeMultiplier = 1.0
    public var lineSizeMultiplier = 1.0
    // Forces, as slider positions
    public var centerStrength = 0.518713248970312
    public var repelStrength = 10.0
    public var linkStrength = 1.0
    public var linkDistance = 250.0
    /// The zoom Obsidian saved with the graph.
    public var scale = 1.0

    public init() {}

    /// The same filters, groups, display and forces: only the saved zoom may differ. Obsidian saves its zoom every
    /// couple of seconds while its graph is open, which is no reason to redraw.
    public func sameLook(as other: ObsidianGraphSettings) -> Bool {
        var a = self, b = other
        a.scale = 1; b.scale = 1
        return a == b
    }

    // MARK: Obsidian's numbers

    /// Obsidian's slider curve for the center and link forces: (0.01^(1-v) - 0.01) / 0.99, 0 at 0 and 1 at 1.
    static func sliderCurve(_ v: Double) -> Double { v >= 1 ? 1 : (pow(0.01, 1 - v) - 0.01) / 0.99 }
    /// The pull toward the center (0.1 at Obsidian's default position).
    public var centerForce: Double { Self.sliderCurve(centerStrength) }
    /// The repulsion between notes: the slider cubed, never below 1 (1,000 at the default position).
    public var repelForce: Double { max(1, repelStrength * repelStrength * repelStrength) }
    public var linkForce: Double { Self.sliderCurve(linkStrength) }

    /// A node's size in Obsidian's units: 3√(weight + 1), from a floor of 8 to a cap of 30, times the size multiplier.
    /// The weight counts links in and out, so a mutual link counts twice.
    public static func nodeSize(weight: Int, multiplier: Double) -> Double {
        multiplier * max(8, min(3 * Double(max(weight, 0) + 1).squareRoot(), 30))
    }

    /// How visible labels are at a zoom: none at half size and below with the default fade, all from full size up.
    public static func labelAlpha(scale: Double, fade: Double) -> Double {
        guard scale > 0 else { return 0 }
        return min(max(log2(scale) + 1 - fade, 0), 1)
    }

    // MARK: Excluded files

    /// Whether app.json's Excluded files hide a file, by its path in the vault.
    public func isIgnored(_ path: String) -> Bool { IgnoreMatcher(ignoreFilters).ignores(path) }

    struct IgnoreMatcher {
        let prefixes: [String]
        let patterns: [NSRegularExpression]
        init(_ filters: [String]) {
            var prefixes: [String] = [], patterns: [NSRegularExpression] = []
            for filter in filters where !filter.isEmpty {
                if filter.count > 2, filter.hasPrefix("/"), filter.hasSuffix("/") {
                    // A pattern that does not compile hides nothing.
                    if let regex = try? NSRegularExpression(pattern: String(filter.dropFirst().dropLast()), options: [.caseInsensitive]) {
                        patterns.append(regex)
                    }
                } else {
                    prefixes.append(ObsidianQuery.fold(filter))
                }
            }
            self.prefixes = prefixes; self.patterns = patterns
        }
        func ignores(_ path: String) -> Bool {
            let folded = ObsidianQuery.fold(path)
            if prefixes.contains(where: { folded.hasPrefix($0) }) { return true }
            let range = NSRange(path.startIndex..., in: path)
            return patterns.contains { $0.firstMatch(in: path, range: range) != nil }
        }
    }

    // MARK: Reading

    /// Settings files are small; anything past this is not a settings file Obsidian wrote.
    static let maxFileSize = 1 << 20

    public static func graphFile(vault: URL) -> URL { vault.appending(path: ".obsidian/graph.json") }
    public static func appFile(vault: URL) -> URL { vault.appending(path: ".obsidian/app.json") }

    public static func read(vault: URL) -> ObsidianGraphSettings {
        parse(graph: readFile(graphFile(vault: vault)), app: readFile(appFile(vault: vault)))
    }

    /// When and how big the two files were: a different stamp means they may have changed and are read again.
    public static func stamp(vault: URL) -> String {
        [graphFile(vault: vault), appFile(vault: vault)].map { url in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "-" }
            let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(date):\((attributes[.size] as? NSNumber)?.intValue ?? 0)"
        }.joined(separator: "|")
    }

    static func readFile(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxFileSize)
    }

    public static func parse(graph: Data?, app: Data?) -> ObsidianGraphSettings {
        var s = ObsidianGraphSettings()
        if let data = graph, let raw = try? JSONDecoder().decode(RawGraph.self, from: data) {
            func range(_ value: Double?, _ bounds: ClosedRange<Double>, _ fallback: Double) -> Double {
                guard let value, value.isFinite else { return fallback }
                return min(max(value, bounds.lowerBound), bounds.upperBound)
            }
            s.search = raw.search ?? s.search
            s.showAttachments = raw.showAttachments ?? s.showAttachments
            s.hideUnresolved = raw.hideUnresolved ?? s.hideUnresolved
            s.showOrphans = raw.showOrphans ?? s.showOrphans
            s.showArrow = raw.showArrow ?? s.showArrow
            s.colorGroups = raw.colorGroups?.compactMap(\.group) ?? []
            s.textFadeMultiplier = range(raw.textFadeMultiplier, -3...3, s.textFadeMultiplier)
            s.nodeSizeMultiplier = range(raw.nodeSizeMultiplier, 0.1...5, s.nodeSizeMultiplier)
            s.lineSizeMultiplier = range(raw.lineSizeMultiplier, 0.1...5, s.lineSizeMultiplier)
            s.centerStrength = range(raw.centerStrength, 0...1, s.centerStrength)
            s.repelStrength = range(raw.repelStrength, 0...20, s.repelStrength)
            s.linkStrength = range(raw.linkStrength, 0...1, s.linkStrength)
            s.linkDistance = range(raw.linkDistance, 30...500, s.linkDistance)
            s.scale = range(raw.scale, (1.0 / 128)...8, s.scale)
        }
        if let data = app, let raw = try? JSONDecoder().decode(RawApp.self, from: data) {
            s.ignoreFilters = raw.userIgnoreFilters ?? []
        }
        return s
    }

    /// graph.json, key by key: a value of the wrong type is left out on its own.
    struct RawGraph: Decodable {
        var search: String?
        var showAttachments: Bool?, hideUnresolved: Bool?, showOrphans: Bool?, showArrow: Bool?
        var colorGroups: [LossyGroup]?
        var textFadeMultiplier: Double?, nodeSizeMultiplier: Double?, lineSizeMultiplier: Double?
        var centerStrength: Double?, repelStrength: Double?, linkStrength: Double?, linkDistance: Double?, scale: Double?

        enum CodingKeys: String, CodingKey {
            case search, showAttachments, hideUnresolved, showOrphans, showArrow, colorGroups, textFadeMultiplier, nodeSizeMultiplier,
                 lineSizeMultiplier, centerStrength, repelStrength, linkStrength, linkDistance, scale
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            search = try? c.decodeIfPresent(String.self, forKey: .search)
            showAttachments = try? c.decodeIfPresent(Bool.self, forKey: .showAttachments)
            hideUnresolved = try? c.decodeIfPresent(Bool.self, forKey: .hideUnresolved)
            showOrphans = try? c.decodeIfPresent(Bool.self, forKey: .showOrphans)
            showArrow = try? c.decodeIfPresent(Bool.self, forKey: .showArrow)
            colorGroups = try? c.decodeIfPresent([LossyGroup].self, forKey: .colorGroups)
            textFadeMultiplier = try? c.decodeIfPresent(Double.self, forKey: .textFadeMultiplier)
            nodeSizeMultiplier = try? c.decodeIfPresent(Double.self, forKey: .nodeSizeMultiplier)
            lineSizeMultiplier = try? c.decodeIfPresent(Double.self, forKey: .lineSizeMultiplier)
            centerStrength = try? c.decodeIfPresent(Double.self, forKey: .centerStrength)
            repelStrength = try? c.decodeIfPresent(Double.self, forKey: .repelStrength)
            linkStrength = try? c.decodeIfPresent(Double.self, forKey: .linkStrength)
            linkDistance = try? c.decodeIfPresent(Double.self, forKey: .linkDistance)
            scale = try? c.decodeIfPresent(Double.self, forKey: .scale)
        }
    }

    /// One color group; a malformed one is dropped without taking the others with it.
    struct LossyGroup: Decodable {
        let group: ColorGroup?
        struct RawColor: Decodable { let a: Double?; let rgb: Int }
        struct Raw: Decodable { let query: String; let color: RawColor }
        init(from decoder: Decoder) throws {
            group = (try? Raw(from: decoder)).map { ColorGroup(query: $0.query, color: GroupColor(rgb: $0.color.rgb, alpha: $0.color.a ?? 1)) }
        }
    }

    struct RawApp: Decodable {
        var userIgnoreFilters: [String]?
        enum CodingKeys: String, CodingKey { case userIgnoreFilters }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userIgnoreFilters = try? c.decodeIfPresent([String].self, forKey: .userIgnoreFilters)
        }
    }
}
