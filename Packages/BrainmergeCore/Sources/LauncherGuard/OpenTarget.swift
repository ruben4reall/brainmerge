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
    static let requirement = "identifier \"\(claudeBundleIdentifier)\" and anchor apple generic"
        + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        + " and certificate leaf[subject.OU] = \"\(anthropicTeam)\""

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
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: app, isDirectory: true) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var required: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &required) == errSecSuccess, let required else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), required) == errSecSuccess
    }
}
