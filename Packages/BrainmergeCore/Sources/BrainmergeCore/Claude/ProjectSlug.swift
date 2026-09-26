import Foundation

public enum ProjectSlug {
    /// Replicates Claude Code's rule: every UTF-16 unit outside [A-Za-z0-9] becomes "-".
    public static func slug(forPath path: String) -> String {
        var out = ""
        for unit in path.utf16 {
            let alnum = (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit)
            if alnum, let scalar = UnicodeScalar(unit) { out.append(Character(scalar)) } else { out.append("-") }
        }
        return out
    }

    /// Past this length Claude Code cuts the name of a project's folder and adds a digest of its own after it.
    public static let maxLength = 200

    /// The folder Claude Code uses for this path in `projectsDir`: the slug, or for a long path the folder that starts
    /// with its first `maxLength` characters (Claude Code's digest cannot be worked out here). Nil for a long path whose
    /// folder Claude Code has not made yet.
    public static func folder(forPath path: String, in projectsDir: URL) -> String? {
        let slug = slug(forPath: path)
        guard slug.count > maxLength else { return slug }
        let head = String(slug.prefix(maxLength))
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: projectsDir.path)) ?? []
        return entries.sorted().first { $0.hasPrefix(head) && $0 != head }
    }

    /// A project's stable name: the last segment of the path; HOME itself is called "home".
    public static func projectName(forPath path: String, home: URL) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if url.path == home.standardizedFileURL.path { return "home" }
        let last = url.lastPathComponent
        return (last.isEmpty || last == "/") ? "root" : last
    }

    /// Name of a project for which only the sessions folder exists: the slug without the HOME prefix.
    public static func projectName(forSlug slug: String, home: URL) -> String {
        let homeSlug = Self.slug(forPath: home.standardizedFileURL.path)
        if slug == homeSlug { return "home" }
        if slug.hasPrefix(homeSlug + "-") {
            let rest = String(slug.dropFirst(homeSlug.count + 1))
            return rest.isEmpty ? slug : rest
        }
        return slug
    }
}
