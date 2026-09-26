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

    /// The person's choice when it is still a valid Claude, else folder order, else the newest version found.
    public func locate(choice: String?) -> URL? {
        if let choice, (try? validate(choice: URL(fileURLWithPath: choice, isDirectory: true))) != nil {
            return URL(fileURLWithPath: choice, isDirectory: true)
        }
        return candidates().first?.url
    }

    /// Valid Claude copies, in the order they are preferred.
    public func candidates() -> [ClaudeApp] {
        let fm = FileManager.default
        var inFolders: [URL] = []
        for folder in folders {
            let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
            inFolders += names.map { folder.appending(path: $0, directoryHint: .isDirectory) }
        }
        var seen = Set<String>()
        var ordered: [ClaudeApp] = []
        for url in inFolders {
            if let app = valid(url), seen.insert(app.url.standardizedFileURL.path).inserted { ordered.append(app) }
        }
        let others = launchServices().compactMap(valid).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
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
