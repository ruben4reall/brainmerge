import Foundation
import BrainmergeCore

/// What the Memory screen's graph can show: a Brainmerge memory, by its id, or an Obsidian vault, by its folder.
public enum GraphSource: Hashable, Sendable {
    case memory(String)
    case vault(String)
}

public struct GraphSourceEntry: Identifiable, Equatable, Sendable {
    public let source: GraphSource
    /// The name in the menu.
    public let name: String
    public var id: GraphSource { source }
}

/// The graph's source menu: every Brainmerge memory, then every Obsidian vault Obsidian lists, with the vault picked
/// by hand while it is the one shown.
public enum GraphSources {
    public static func menu(brains: [MemoryFolder], vaults: [URL], chosen: String?) -> (memories: [GraphSourceEntry], vaults: [GraphSourceEntry]) {
        let memories = brains.map { GraphSourceEntry(source: .memory($0.id), name: brains.count == 1 ? "Brainmerge memory" : $0.name) }
        var folders: [URL] = []
        var seen = Set<String>()
        let chosenURL = chosen.map { URL(fileURLWithPath: $0, isDirectory: true) }
        for url in vaults + [chosenURL].compactMap({ $0 }) {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted { folders.append(url.standardizedFileURL) }
        }
        // Two vaults with one name are told apart by the folder they sit in.
        var byName: [String: Int] = [:]
        for url in folders { byName[url.lastPathComponent, default: 0] += 1 }
        let entries = folders.map { url -> GraphSourceEntry in
            let name = url.lastPathComponent
            let shown = (byName[name] ?? 0) > 1 ? "\(name) · \(url.deletingLastPathComponent().lastPathComponent)" : name
            // The chosen vault keeps the spelling it was saved with, so the menu's selection matches it.
            let path = chosenURL.flatMap { $0.standardizedFileURL.path == url.path ? chosen : nil } ?? url.path
            return GraphSourceEntry(source: .vault(path), name: shown)
        }
        return (memories, entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    /// The source's name on the menu's button.
    public static func title(of source: GraphSource, brains: [MemoryFolder]) -> String {
        switch source {
        case .memory(let id):
            guard brains.count > 1, let folder = brains.first(where: { $0.id == id }) else { return "Brainmerge memory" }
            return "Brainmerge memory · \(folder.name)"
        case .vault(let path):
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.lastPathComponent
        }
    }
}
