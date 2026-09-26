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
    ///
    /// A project's index (its `MEMORY.md`) changes with the notes it lists: it counts only when nothing else changed, so
    /// one new note and its line in the index is "remembered something", never "2 things".
    public static func sentence(files: [String], project: String?, byYou: Bool = false) -> String {
        let all = files.filter { $0.hasPrefix("memory/") }
        if all.isEmpty {
            if files.contains("BRAIN.md") { return byYou ? "edited the memory's instructions" : "changed the memory's instructions" }
            return "\(byYou ? "edited" : "updated") \(count(files.count, "file"))"
        }
        let others = all.filter { !isIndex($0) }
        let notes = others.isEmpty ? all : others
        // An index of another project, left out, no longer spreads the save over two projects.
        let project = project ?? Self.project(files: notes)
        let projects = Set(notes.compactMap(Self.project(of:)))
        if let project, notes.count == 1 {
            if byYou { return "edited a note about \(project)" }
            return isIndex(notes[0]) ? "updated its notes about \(project)" : "remembered something about \(project)"
        }
        if let project { return byYou ? "edited \(notes.count) notes about \(project)" : "remembered \(notes.count) things about \(project)" }
        let verb = byYou ? "edited" : "updated"
        if projects.isEmpty { return "\(verb) \(count(notes.count, "note"))" }
        return "\(verb) \(notes.count) notes across \(projects.count) projects"
    }

    /// A project's index, `memory/<project>/MEMORY.md`.
    static func isIndex(_ path: String) -> Bool { path.hasSuffix("/MEMORY.md") }

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

    /// Tidy's commits, all yours: "filed 2 notes under brainmerge", "kept one copy of deploy.md", "hid 3 empty folders from Tidy".
    public static func filed(_ notes: Int, under project: String) -> String {
        "filed \(notes == 1 ? "a note" : "\(notes) notes") under \(project)"
    }
    public static func kept(_ name: String) -> String { "kept one copy of \(name)" }
    public static func hid(_ folders: Int) -> String { "hid \(folders == 1 ? "an empty folder" : "\(folders) empty folders") from Tidy" }

    /// A Tidy commit's own words, found back in a message of yours ("You filed 2 notes under brainmerge" gives "filed 2 notes
    /// under brainmerge"): they say what the click did, which its files alone cannot. Nil for any other message.
    public static func tidy(message: String) -> String? {
        let you = "You "
        guard message.hasPrefix(you) else { return nil }
        let words = String(message.dropFirst(you.count))
        let isTidy = words.hasPrefix("filed ") || words.hasPrefix("kept one copy of ") || (words.hasPrefix("hid ") && words.hasSuffix(" from Tidy"))
        return isTidy ? words : nil
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
