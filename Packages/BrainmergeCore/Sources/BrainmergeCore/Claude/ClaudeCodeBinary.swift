import Foundation
import LauncherGuard

/// The official Claude Code that "Check limits" may run. Found at an absolute path, never through PATH (an app opened
/// from Finder has no `~/.local/bin` in it, and a PATH can be pointed anywhere), and only when Anthropic signed it,
/// checked with the Security framework like the first account's own app checks Claude. Nothing here runs it.
public enum ClaudeCodeBinary {
    /// The identifier Anthropic signs Claude Code with.
    public static let identifier = "com.anthropic.claude-code"

    /// Where the installers put it, in the order looked at: the native installer's link, then Homebrew's two prefixes.
    public static func candidates(home: URL) -> [String] {
        [home.appending(path: ".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    public enum Resolution: Equatable, Sendable {
        /// The program to run: where the link points, so the link cannot be swapped between the check and the run.
        case found(String)
        case notFound
        /// The first one found, which Anthropic did not sign: nothing else is tried, it is the one the person uses.
        case notSigned(String)
    }

    /// The first candidate that is a program (a broken link or a folder is passed over), if Anthropic signed it.
    public static func resolve(candidates: [String], isSigned: (String) -> Bool = isSignedByAnthropic) -> Resolution {
        for candidate in candidates {
            let target = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target, isDirectory: &isFolder), !isFolder.boolValue else { continue }
            return isSigned(target) ? .found(target) : .notSigned(candidate)
        }
        return .notFound
    }

    /// Signed with Anthropic's Developer ID under Claude Code's identifier.
    public static func isSignedByAnthropic(_ path: String) -> Bool {
        OpenTarget.isSignedByAnthropic(path, identifier: identifier)
    }
}
