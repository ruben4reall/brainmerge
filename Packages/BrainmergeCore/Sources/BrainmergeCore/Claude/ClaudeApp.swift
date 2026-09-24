import Foundation

public struct ClaudeApp: Equatable, Sendable {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    public let url: URL
    public let version: String
    public let bundleIdentifier: String

    public var executable: URL { url.appending(path: "Contents/MacOS/Claude") }
    public var icon: URL { url.appending(path: "Contents/Resources/electron.icns") }
    public var infoPlist: URL { url.appending(path: "Contents/Info.plist") }

    /// `/Applications/Claude.app`, or the path forced by BRAINMERGE_CLAUDE_APP (tests).
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let o = environment["BRAINMERGE_CLAUDE_APP"], !o.isEmpty {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        return URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true)
    }

    public static func detect(at url: URL = ClaudeApp.defaultURL()) throws -> ClaudeApp {
        let plist = url.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: plist.path) else {
            throw BrainmergeError.claudeAppNotFound(url.path)
        }
        let info = try Plist.read(plist)
        guard let version = info["CFBundleShortVersionString"] as? String,
              let bundle = info["CFBundleIdentifier"] as? String
        else { throw BrainmergeError.invalidPlist(plist.path) }
        return ClaudeApp(url: url, version: version, bundleIdentifier: bundle)
    }
}
