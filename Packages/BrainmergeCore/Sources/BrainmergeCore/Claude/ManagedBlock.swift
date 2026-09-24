import Foundation

/// The block that Brainmerge owns in a profile's CLAUDE.md. Everything else belongs to the person.
public enum ManagedBlock {
    public static let start = "<!-- brainmerge:start -->"
    public static let end = "<!-- brainmerge:end -->"

    public static func render(identityName: String, slug: String, brainPath: String) -> String {
        // Claude Code's import parser stops the path at the first unescaped space.
        let importPath = brainPath.replacingOccurrences(of: " ", with: "\\ ")
        return """
        \(start)
        You are the Claude identity "\(identityName)" (slug \(slug)), managed by Brainmerge. Your shared brain is at \(brainPath).
        @\(importPath)/BRAIN.md
        \(end)
        """
    }

    public static func contains(_ content: String) -> Bool { range(in: content) != nil }

    /// Replaces the existing block, or appends it at the end after a blank line.
    public static func upsert(in content: String, block: String) -> String {
        if let range = range(in: content) {
            return content.replacingCharacters(in: range, with: block)
        }
        if content.isEmpty { return block + "\n" }
        let separator = content.hasSuffix("\n\n") ? "" : (content.hasSuffix("\n") ? "\n" : "\n\n")
        return content + separator + block + "\n"
    }

    /// Removes the block and the blank line it leaves behind.
    public static func remove(from content: String) -> String {
        guard let range = range(in: content) else { return content }
        var chars = Array(content)
        let lo = content.distance(from: content.startIndex, to: range.lowerBound)
        var hi = content.distance(from: content.startIndex, to: range.upperBound)
        if hi < chars.count, chars[hi] == "\n" { hi += 1 }
        chars.removeSubrange(lo..<hi)
        while lo >= 2, lo < chars.count, chars[lo] == "\n", chars[lo - 1] == "\n", chars[lo - 2] == "\n" {
            chars.remove(at: lo)
        }
        while chars.count >= 2, chars[chars.count - 1] == "\n", chars[chars.count - 2] == "\n" {
            chars.removeLast()
        }
        return String(chars)
    }

    static func range(in content: String) -> Range<String.Index>? {
        guard let s = content.range(of: start),
              let e = content.range(of: end, range: s.upperBound..<content.endIndex)
        else { return nil }
        return s.lowerBound..<e.upperBound
    }
}
