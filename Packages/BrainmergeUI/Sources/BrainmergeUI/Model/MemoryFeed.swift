import Foundation
import BrainmergeCore

public struct MemoryEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let slug: String?
    public let name: String
    public let tint: Tint
    public let sentence: String
    public let detail: String
}

/// Turns the brain's commits into everyday sentences.
public enum MemoryFeed {
    static let authorSuffix = "@brainmerge.local"

    public static func events(from entries: [BrainGit.Entry], identities: [Identity]) -> [MemoryEvent] {
        entries.map { e in
            let slug = e.authorEmail.hasSuffix(authorSuffix) ? String(e.authorEmail.dropLast(authorSuffix.count)) : nil
            let identity = slug.flatMap { s in identities.first { $0.slug == s } }
            let projects = Set(e.files.compactMap(project(of:)))
            let project = projects.count == 1 ? projects.first : nil
            let files = e.files.map { ($0 as NSString).lastPathComponent }
            let detail = [project, files.count <= 2 ? files.joined(separator: ", ") : "\(files.count) files"].compactMap { $0 }.joined(separator: " · ")
            let external = e.authorName.trimmingCharacters(in: .whitespaces)
            return MemoryEvent(id: e.hash, date: e.date, slug: slug, name: identity?.name ?? (external.isEmpty ? "Someone" : external), tint: identity?.tint ?? .gray,
                               sentence: sentence(files: e.files, project: project), detail: detail)
        }
    }

    public static func sentence(files: [String], project: String?) -> String {
        let memoryFiles = files.filter { $0.hasPrefix("memory/") }
        if memoryFiles.isEmpty {
            return files.contains("BRAIN.md") ? "changed the memory's instructions" : "updated \(files.count) file\(files.count > 1 ? "s" : "")"
        }
        let projects = Set(memoryFiles.compactMap(project(of:)))
        if let project, memoryFiles.count == 1 {
            return memoryFiles[0].hasSuffix("/MEMORY.md") ? "updated its notes about \(project)" : "remembered something about \(project)"
        }
        if let project { return "updated \(memoryFiles.count) notes about \(project)" }
        if projects.isEmpty { return "updated \(memoryFiles.count) note\(memoryFiles.count > 1 ? "s" : "")" }
        return "updated \(memoryFiles.count) notes across \(projects.count) projects"
    }

    public static func counts(_ entries: [BrainGit.Entry]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for e in entries where e.authorEmail.hasSuffix(authorSuffix) {
            counts[String(e.authorEmail.dropLast(authorSuffix.count)), default: 0] += 1
        }
        return counts
    }

    static func project(of path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count >= 3 && parts[0] == "memory" ? String(parts[1]) : nil
    }
}
