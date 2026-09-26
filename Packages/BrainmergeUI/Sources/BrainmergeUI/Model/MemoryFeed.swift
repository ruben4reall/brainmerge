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

/// Turns the brain's commits into everyday sentences, the command line's own words (MemorySentence). The person's own
/// edits, saved by the app (OwnEdits), read "You", in gray, and are no account's saves. A click in the Tidy tab keeps its
/// own words ("You filed 2 notes under brainmerge"), which its files alone could not say.
public enum MemoryFeed {
    static let authorSuffix = "@brainmerge.local"

    public static func events(from entries: [BrainGit.Entry], identities: [Identity]) -> [MemoryEvent] {
        entries.map { e in
            let byYou = e.authorEmail == OwnEdits.author.email
            let slug = byYou ? nil : accountSlug(e.authorEmail)
            let identity = slug.flatMap { s in identities.first { $0.slug == s } }
            let project = MemorySentence.project(files: e.files)
            let files = e.files.map { ($0 as NSString).lastPathComponent }
            let detail = [project, files.count <= 2 ? files.joined(separator: ", ") : "\(files.count) files"].compactMap { $0 }.joined(separator: " · ")
            let external = e.authorName.trimmingCharacters(in: .whitespaces)
            let name = byYou ? OwnEdits.author.name : identity?.name ?? (external.isEmpty ? "Someone" : external)
            return MemoryEvent(id: e.hash, date: e.date, slug: slug, name: name, tint: identity?.tint ?? .gray,
                               sentence: (byYou ? MemorySentence.tidy(message: e.message) : nil)
                                   ?? MemorySentence.sentence(files: e.files, project: project, byYou: byYou), detail: detail)
        }
    }

    /// The rows above the previous top row: new saves, newest first. None on a first read, nor when the two lists share
    /// no row (another memory, a history written again).
    public static func arrivals(from old: [String], to new: [String]) -> [String] {
        guard let top = old.first, let index = new.firstIndex(of: top) else { return [] }
        return Array(new[..<index])
    }

    public static func counts(_ entries: [BrainGit.Entry]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for e in entries { if let slug = accountSlug(e.authorEmail) { counts[slug, default: 0] += 1 } }
        return counts
    }

    /// The account a save is by, from its address; nil for the person's own edits and for authors outside Brainmerge.
    static func accountSlug(_ email: String) -> String? {
        guard email.hasSuffix(authorSuffix), email != OwnEdits.author.email else { return nil }
        return String(email.dropLast(authorSuffix.count))
    }
}
