import Foundation

/// The words of a save, in one place: the command line writes them as the commit message and the Memory screen shows
/// them, so `git log` and the app say the same thing. An account "remembers"; the person, outside Claude, "edits".
public enum MemorySentence {
    /// "Work remembered 2 things about acme", "You edited a note about acme".
    public static func message(name: String, files: [String], byYou: Bool = false) -> String {
        "\(name) \(sentence(files: files, byYou: byYou))"
    }

    public static func sentence(files: [String], byYou: Bool = false) -> String {
        sentence(files: files, project: project(files: files), byYou: byYou)
    }

    /// `project` is the one project folder every file is in, nil when there are several or none.
    public static func sentence(files: [String], project: String?, byYou: Bool = false) -> String {
        let notes = files.filter { $0.hasPrefix("memory/") }
        if notes.isEmpty {
            if files.contains("BRAIN.md") { return byYou ? "edited the memory's instructions" : "changed the memory's instructions" }
            return "\(byYou ? "edited" : "updated") \(count(files.count, "file"))"
        }
        let projects = Set(notes.compactMap(Self.project(of:)))
        if let project, notes.count == 1 {
            if byYou { return "edited a note about \(project)" }
            return notes[0].hasSuffix("/MEMORY.md") ? "updated its notes about \(project)" : "remembered something about \(project)"
        }
        if let project { return byYou ? "edited \(notes.count) notes about \(project)" : "remembered \(notes.count) things about \(project)" }
        let verb = byYou ? "edited" : "updated"
        if projects.isEmpty { return "\(verb) \(count(notes.count, "note"))" }
        return "\(verb) \(notes.count) notes across \(projects.count) projects"
    }

    /// The project folder a note is in: `memory/<project>/…`. A note at the top of `memory/` has none.
    public static func project(of path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count >= 3 && parts[0] == "memory" ? String(parts[1]) : nil
    }

    /// The one project every note of a save is about, nil when there are several or none.
    public static func project(files: [String]) -> String? {
        let projects = Set(files.compactMap(project(of:)))
        return projects.count == 1 ? projects.first : nil
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
