import Foundation

/// What Obsidian's graph shows of a vault, and in which colors, from the vault's own settings.
///
/// The order is Obsidian's: Excluded files and the search filter hide files, attachments show only when asked for,
/// a link to nothing shows only when unresolved links are asked for and a shown file points at it, orphans are judged
/// on what is left. Then each shown file takes the color of the first group whose query it matches.
public enum ObsidianGraphFilter {
    public struct Shown: Equatable, Sendable {
        public var graph: MemoryGraph
        /// The color group of each node that matched one, by node id.
        public var colors: [String: ObsidianGraphSettings.GroupColor]
    }

    /// Whether the vault shows a file, from its path alone: the search filter, the Excluded files and the attachments
    /// setting. What depends on links (orphans, unresolved links) is judged on the graph afterwards. The graph's builder
    /// uses it too, so its cap on notes counts only the files that can show.
    public static func showsFile(_ settings: ObsidianGraphSettings) -> (_ path: String, _ attachment: Bool) -> Bool {
        let search = ObsidianQuery(settings.search)
        let ignore = ObsidianGraphSettings.IgnoreMatcher(settings.ignoreFilters)
        let attachments = settings.showAttachments
        return { path, attachment in
            (attachments || !attachment) && !ignore.ignores(path) && search.matches(ObsidianQuery.Folded(path))
        }
    }

    public static func apply(_ settings: ObsidianGraphSettings, to graph: MemoryGraph) -> Shown {
        let shows = showsFile(settings)
        var visible = Set<String>()
        for node in graph.nodes {
            switch node.kind {
            case .note, .attachment:
                guard shows(node.file ?? node.id, node.kind == .attachment) else { continue }
                visible.insert(node.id)
            case .project:
                visible.insert(node.id)
            case .unresolved:
                continue
            }
        }
        if !settings.hideUnresolved {
            let unresolved = Set(graph.nodes.lazy.filter { $0.kind == .unresolved }.map(\.id))
            for link in graph.links where visible.contains(link.source) && unresolved.contains(link.target) { visible.insert(link.target) }
        }
        var edges = graph.edges.filter { visible.contains($0.from) && visible.contains($0.to) }
        if !settings.showOrphans {
            var linked = Set<String>()
            for edge in edges { linked.insert(edge.from); linked.insert(edge.to) }
            visible.formIntersection(linked)
            edges = edges.filter { visible.contains($0.from) && visible.contains($0.to) }
        }
        let shown = MemoryGraph(nodes: graph.nodes.filter { visible.contains($0.id) }, edges: edges,
                                links: graph.links.filter { visible.contains($0.source) && visible.contains($0.target) })
        // Groups apply to files; one that Brainmerge cannot evaluate at all colors nothing.
        let groups = settings.colorGroups.map { (query: ObsidianQuery($0.query), color: $0.color) }.filter { !$0.query.isEmpty }
        var colors: [String: ObsidianGraphSettings.GroupColor] = [:]
        if !groups.isEmpty {
            for node in shown.nodes where node.kind == .note || node.kind == .attachment {
                let path = ObsidianQuery.Folded(node.file ?? node.id)
                if let group = groups.first(where: { $0.query.matches(path) }) { colors[node.id] = group.color }
            }
        }
        return Shown(graph: shown, colors: colors)
    }
}
