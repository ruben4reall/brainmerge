import Foundation

/// Names of accounts and memories end up in file names, plists, git authors and Claude's instructions:
/// they are kept to one clean line, without control characters, of bounded length, never starting with a dot.
public enum NameRules {
    public static let maxLength = 60

    public static func clean(_ raw: String) -> String {
        let spaced = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : Character(scalar)
        }
        var words = String(spaced).split(whereSeparator: \.isWhitespace).map(String.init)
        var name = words.joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > maxLength {
            name = String(name.prefix(maxLength))
            words = name.split(whereSeparator: \.isWhitespace).map(String.init)
            name = words.joined(separator: " ")
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Git drops these from an author's name, and refuses a name made only of them.
    static let gitStrips = Set(" .,:;<>\"\\'")

    /// An account's name signs its saves: it needs one character git keeps.
    public static func isUsableForAccount(_ cleaned: String) -> Bool { cleaned.contains { !gitStrips.contains($0) } }

}
