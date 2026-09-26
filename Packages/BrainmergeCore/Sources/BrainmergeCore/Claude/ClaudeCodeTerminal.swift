import Foundation

/// Claude Code in a terminal, per account: `brainmerge code <slug>` and the `claude-<slug>` links. Pure parts, so the
/// command's own code only reads PATH (BRAINMERGE_HOME is read by the setup every command shares), sets or unsets
/// CLAUDE_CONFIG_DIR and hands over with execv.
public enum ClaudeCodeTerminal {
    public static let notFound = "Claude Code is not installed or not on your PATH."
    public static let linkPrefix = "claude-"

    /// The first executable named exactly `claude` on PATH. Empty and relative entries are skipped (a relative entry
    /// runs whatever sits in the current folder), and so is a `claude` that is one of Brainmerge's own links.
    public static func resolve(path: String?, isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                               destination: (String) -> String? = { try? FileManager.default.destinationOfSymbolicLink(atPath: $0) }) -> String? {
        for entry in (path ?? "").split(separator: ":", omittingEmptySubsequences: true).map(String.init) where entry.hasPrefix("/") {
            let candidate = (entry as NSString).appendingPathComponent("claude")
            guard isExecutable(candidate) else { continue }
            if let target = destination(candidate), CLIInstaller.madeByBrainmerge(destination: target) { continue }
            return candidate
        }
        return nil
    }

    /// For `brainmerge env`: the primary's profile is ~/.claude, Claude Code's default, so the variable goes.
    public static func envLine(configDir: String?) -> String {
        guard let configDir else { return "unset CLAUDE_CONFIG_DIR" }
        return "export CLAUDE_CONFIG_DIR='\(configDir.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// The arguments for the parser. Called as `claude-<known slug>`, it is `code <slug>` with the rest untouched.
    public static func dispatch(_ argv: [String], slugs: Set<String>) -> [String] {
        let rest = Array(argv.dropFirst())
        guard let first = argv.first else { return rest }
        let name = (first as NSString).lastPathComponent
        guard name.hasPrefix(linkPrefix) else { return rest }
        let slug = String(name.dropFirst(linkPrefix.count))
        return slugs.contains(slug) ? ["code", slug] + rest : rest
    }

    /// The terminal tab's title (OSC 2). Control characters of the name are dropped so it cannot end the sequence.
    public static func title(name: String) -> String {
        let clean = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        return "\u{1B}]2;Claude: \(clean)\u{07}"
    }
}
