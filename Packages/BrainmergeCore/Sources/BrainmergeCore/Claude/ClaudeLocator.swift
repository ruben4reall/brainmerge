import CoreServices
import Foundation
import LauncherGuard

/// Finds the official Claude app wherever it is installed: /Applications, ~/Applications, or anywhere Launch Services
/// knows it. Only bundles Anthropic signed count (the same Security framework check the first account's own app uses),
/// never Brainmerge's own apps nor a copy made by hand. Nothing here opens, runs or changes anything.
public struct ClaudeLocator: Sendable {
    public let paths: Paths
    /// Searched in this order: /Applications first, then ~/Applications (only ~/Applications for a test or demo home).
    public let folders: [URL]
    let launchServices: @Sendable () -> [URL]
    let isSigned: @Sendable (String) -> Bool

    public init(paths: Paths, folders: [URL]? = nil,
                launchServices: @escaping @Sendable () -> [URL] = ClaudeLocator.registeredCopies,
                isSigned: @escaping @Sendable (String) -> Bool = { OpenTarget.isSignedByAnthropic($0) }) {
        self.paths = paths
        self.folders = folders ?? ExistingApps.folders(for: paths).reversed()
        self.launchServices = launchServices; self.isSigned = isSigned
    }

    /// Every Claude that Launch Services has registered, by bundle identifier.
    public static let registeredCopies: @Sendable () -> [URL] = {
        (LSCopyApplicationURLsForBundleIdentifier(ClaudeApp.bundleIdentifier as CFString, nil)?.takeRetainedValue() as? [URL]) ?? []
    }

    /// Where Brainmerge looks for Claude: the test override, else the person's choice or the first one found, else the usual place.
    public static func resolvedURL(paths: Paths, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let forced = environment["BRAINMERGE_CLAUDE_APP"], !forced.isEmpty { return ClaudeApp.defaultURL(environment: environment) }
        let choice = (try? StateStore(paths: paths).load())?.claudeAppPath
        return ClaudeLocator(paths: paths).locate(choice: choice) ?? ClaudeApp.defaultURL(environment: environment)
    }

    /// The person's choice when it is still a valid Claude, else Claude.app at its usual place, else the newest copy found.
    public func locate(choice: String?) -> URL? {
        if let choice, (try? validate(choice: URL(fileURLWithPath: choice, isDirectory: true))) != nil {
            return URL(fileURLWithPath: choice, isDirectory: true)
        }
        return candidates().first?.url
    }

    /// Valid Claude copies, in the order they are preferred: `Claude.app` at its usual place (/Applications, then
    /// ~/Applications), where Claude installs and updates itself, then any other copy, newest first. A copy under another
    /// name (a Finder duplicate left behind, "Claude copy.app") is never picked while Claude itself is there.
    public func candidates() -> [ClaudeApp] {
        let fm = FileManager.default
        var usual: [URL] = [], copies: [URL] = []
        for folder in folders {
            let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
            for name in names {
                let url = folder.appending(path: name, directoryHint: .isDirectory)
                if name == "Claude.app" { usual.append(url) } else { copies.append(url) }
            }
        }
        var seen = Set<String>()
        let ordered = usual.compactMap(valid).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
        let others = (copies + launchServices()).compactMap(valid).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .enumerated()
            .sorted { a, b in
                let order = a.element.version.compare(b.element.version, options: .numeric)
                return order == .orderedSame ? a.offset < b.offset : order == .orderedDescending
            }
            .map(\.element)
        return ordered + others
    }

    /// Refuses anything but Anthropic's Claude: not Claude, one of Brainmerge's own apps, a hand-made copy, or unsigned.
    public func validate(choice url: URL) throws {
        guard let app = try? ClaudeApp.detect(at: url), app.bundleIdentifier == ClaudeApp.bundleIdentifier else {
            throw BrainmergeError.claudeAppNotFound(url.path)
        }
        guard !isBrainmergesOwn(url), !isHandMade(url), isSigned(url.path) else { throw BrainmergeError.claudeNotSigned(url.path) }
    }

    func valid(_ url: URL) -> ClaudeApp? {
        guard (try? validate(choice: url)) != nil else { return nil }
        return try? ClaudeApp.detect(at: url)
    }

    func isBrainmergesOwn(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(paths.launchersDir.standardizedFileURL.path + "/")
    }

    /// A copy whose program is a launch script naming an account's folders (see ExistingApps).
    func isHandMade(_ url: URL) -> Bool {
        let scanner = ExistingApps(paths: paths, claudeAppURL: paths.launchersDir, folders: [url.deletingLastPathComponent()])
        return scanner.scan().contains { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }
    }
}
