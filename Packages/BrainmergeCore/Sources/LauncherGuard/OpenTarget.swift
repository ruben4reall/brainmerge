import Foundation
import Security

/// What the primary account's own app may open: Anthropic's Claude, at the exact path its builder pinned, and nothing
/// else. The app then asks macOS to open Claude (`open -a`), with no folder and no environment of its own, so Claude
/// runs on its default folders exactly as when it is opened from Finder. Nothing here opens, runs or changes anything:
/// it reads a property list and a code signature.
public enum OpenTarget {
    /// The Info.plist key of the opener that holds the Claude path written when it was built.
    public static let pinKey = "BrainmergeOpensClaudeAt"
    public static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"
    /// Anthropic's Developer ID team.
    public static let anthropicTeam = "Q6L2SF6YDW"

    /// Claude's own designated requirement: a Developer ID app from Anthropic's team, with Claude's identifier.
    static let requirement = requirement(identifier: claudeBundleIdentifier)

    /// Code signed with Anthropic's Developer ID (team `Q6L2SF6YDW`) under exactly this identifier.
    static func requirement(identifier: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(anthropicTeam)\""
    }

    public enum Refusal: Equatable, Sendable {
        /// Not an absolute path to an app bundle, or a path that climbs out with `..`.
        case notAnApp
        /// Another path than the one pinned when the app was built.
        case notPinned
        /// The bundle there does not say it is Claude.
        case notClaude
        /// It says it is Claude, but Anthropic did not sign it: a hand-made or tinted copy, or something else.
        case notSignedByAnthropic

        public var reason: String {
            switch self {
            case .notAnApp: "not an absolute path to an app"
            case .notPinned: "not the Claude this app was built for"
            case .notClaude: "not Claude"
            case .notSignedByAnthropic: "not signed by Anthropic"
            }
        }
    }

    /// Why `openApp` must not be opened, or nil when it is Anthropic's Claude at the pinned path. Cheapest checks first.
    public static func refusal(openApp: String, pinned: String?) -> Refusal? {
        guard openApp.hasPrefix("/"), openApp.hasSuffix(".app"), !openApp.contains("/../"), !openApp.hasSuffix("/..") else { return .notAnApp }
        guard let pinned, openApp == pinned else { return .notPinned }
        guard bundleIdentifier(of: openApp) == claudeBundleIdentifier else { return .notClaude }
        guard isSignedByAnthropic(openApp) else { return .notSignedByAnthropic }
        return nil
    }

    /// The bundle identifier its Info.plist declares.
    static func bundleIdentifier(of app: String) -> String? {
        let plist = URL(fileURLWithPath: app, isDirectory: true).appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    /// Anthropic's signature on the app, checked by the Security framework (no subprocess). The resources are not hashed
    /// again on every click: the signature of the main executable and the Info.plist identifies the app.
    public static func isSignedByAnthropic(_ app: String) -> Bool {
        isSigned(URL(fileURLWithPath: app, isDirectory: true), requirement: requirement)
    }

    /// The same check for any code, an app or a single program such as Claude Code, under the identifier it must carry.
    public static func isSignedByAnthropic(_ path: String, identifier: String) -> Bool {
        isSigned(URL(fileURLWithPath: path), requirement: requirement(identifier: identifier))
    }

    static func isSigned(_ url: URL, requirement: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var required: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &required) == errSecSuccess, let required else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), required) == errSecSuccess
    }

    /// What the opener runs once every check passed: a program, its whole argument list, and the variables removed first.
    public struct Command: Equatable, Sendable {
        public let path: String
        public let arguments: [String]
        public let unset: [String]
    }

    /// `open -a <Claude>`: macOS opens Claude, or brings it forward, on its own folders. None of the opener's own
    /// arguments is passed on, and no Claude Code folder is left in the environment.
    public static func command(opening app: String) -> Command {
        Command(path: "/usr/bin/open", arguments: ["open", "-a", app], unset: ["CLAUDE_CONFIG_DIR"])
    }
}
