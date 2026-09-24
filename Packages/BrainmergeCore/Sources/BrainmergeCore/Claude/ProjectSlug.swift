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
