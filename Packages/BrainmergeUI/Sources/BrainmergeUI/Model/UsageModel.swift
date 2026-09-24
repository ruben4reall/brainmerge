import Foundation
import BrainmergeCore

/// Usage for one account, or several accounts that share the same history (a single transcripts folder).
public struct AccountUsage: Identifiable, Equatable, Sendable {
    public var slugs: [String]
    public var names: [String]
    public var tints: [Tint]
    public var summary: UsageSummary
    public var shared: Bool { slugs.count > 1 }
    public var id: String { slugs.joined(separator: "+") }
    public init(slugs: [String], names: [String], tints: [Tint], summary: UsageSummary) {
        self.slugs = slugs; self.names = names; self.tints = tints; self.summary = summary
    }
}

/// Readable token counts: 999, 12.4k, 1.3M.
public enum TokenFormat {
    public static func short(_ n: Int) -> String {
        func tenth(_ value: Double) -> String {   // rounded to the nearest tenth (1.25 gives 1.3), without a trailing ".0"
            let rounded = (value * 10).rounded() / 10
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        }
        switch n {
        case ..<1000: return "\(n)"
        case ..<999_500: return tenth(Double(n) / 1000) + "k"
        default: return tenth(Double(n) / 1_000_000) + "M"
        }
    }
}

/// Groups identities by real `projects` folder: two accounts with shared history read the same folder.
enum UsageGrouping {
    static func groups(of identities: [Identity], paths: Paths) -> [[Identity]] {
        var order: [String] = []
        var byRoot: [String: [Identity]] = [:]
        for identity in identities {
            let projects = CLIProfile(directory: identity.cliProfile(in: paths)).projectsDir
            let key = projects.resolvingSymlinksInPath().path
            if byRoot[key] == nil { order.append(key) }
            byRoot[key, default: []].append(identity)
        }
        return order.compactMap { byRoot[$0] }
    }
}
