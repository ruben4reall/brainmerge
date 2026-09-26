import Foundation
import LauncherGuard

/// A Chromium browser Brainmerge can open in a chosen profile, so each account has its own browser with its own Claude
/// extension and logins.
public enum ChromiumBrowser: String, Codable, CaseIterable, Sendable {
    case chrome, arc, brave, edge

    public var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .brave: "Brave"
        case .edge: "Edge"
        }
    }
    var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }
    var appName: String {
        switch self {
        case .chrome: "Google Chrome.app"
        case .arc: "Arc.app"
        case .brave: "Brave Browser.app"
        case .edge: "Microsoft Edge.app"
        }
    }
    /// Its list of profiles, under ~/Library/Application Support.
    var localState: String {
        switch self {
        case .chrome: "Google/Chrome/Local State"
        case .arc: "Arc/User Data/Local State"
        case .brave: "BraveSoftware/Brave-Browser/Local State"
        case .edge: "Microsoft Edge/Local State"
        }
    }
}

/// A profile of a browser: its folder id (what `--profile-directory` takes) and the name the browser shows.
public struct BrowserProfile: Equatable, Hashable, Sendable {
    public let browser: ChromiumBrowser
    public let directory: String
    public let name: String
    public init(browser: ChromiumBrowser, directory: String, name: String) {
        self.browser = browser; self.directory = directory; self.name = name
    }
}

/// The browser profile that goes with an account, kept on its Identity.
public struct BrowserChoice: Codable, Equatable, Hashable, Sendable {
    public var browser: ChromiumBrowser
    public var directory: String
    public init(browser: ChromiumBrowser, directory: String) { self.browser = browser; self.directory = directory }
}

extension KeyedDecodingContainer {
    /// A pick this version cannot read (a browser a newer Brainmerge knows) reads as none: the account, and the whole
    /// state with it, still load. Used by every optional BrowserChoice, such as Identity's.
    public func decodeIfPresent(_ type: BrowserChoice.Type, forKey key: Key) throws -> BrowserChoice? {
        try? decode(BrowserChoice.self, forKey: key)
    }
}

/// An installed browser with its app and its profiles.
public struct InstalledBrowser: Equatable, Sendable {
    public let browser: ChromiumBrowser
    public let app: URL
    public let profiles: [BrowserProfile]
    public init(browser: ChromiumBrowser, app: URL, profiles: [BrowserProfile]) {
        self.browser = browser; self.app = app; self.profiles = profiles
    }
}

/// Reads browsers' profile lists and builds the command that opens one. `Local State` also records each profile's Google
/// address and ids next to its name: only the folder id and `name` are decoded, by typed keys, nothing else.
public enum BrowserProfiles {
    /// The documented page where a Claude account's connectors (Gmail, Calendar, Drive) are managed.
    public static let connectorsURL = "https://claude.ai/customize/connectors"

    public struct Command: Equatable, Sendable {
        public let path: String
        public let arguments: [String]
        public init(path: String, arguments: [String]) { self.path = path; self.arguments = arguments }
    }

    /// The profiles in a `Local State` file, by name; none when it is not what is expected.
    public static func profiles(localState data: Data, browser: ChromiumBrowser) -> [BrowserProfile] {
        guard let root = try? JSONDecoder().decode(StateRoot.self, from: data) else { return [] }
        return root.profiles.compactMap { directory, name in
            guard isValidDirectory(directory), let name, !name.isEmpty else { return nil }
            return BrowserProfile(browser: browser, directory: directory, name: name)
        }.sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.directory < b.directory : order == .orderedAscending
        }
    }

    /// A folder id as browsers make them ("Default", "Profile 2"): one plain name, nothing that climbs or looks like an option.
    public static func isValidDirectory(_ directory: String) -> Bool {
        guard !directory.isEmpty, directory.count <= 64, !directory.hasPrefix("."), !directory.hasPrefix("-") else { return false }
        return directory.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || " _-".unicodeScalars.contains($0) }
    }

    /// The browsers installed in `applications` (by default /Applications and ~/Applications) whose app says it is that
    /// browser and that have a list of profiles.
    public static func available(home: URL, applications: [URL]? = nil) -> [InstalledBrowser] {
        let roots = applications ?? [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")]
        let support = home.appending(path: "Library/Application Support")
        return ChromiumBrowser.allCases.compactMap { browser in
            guard let app = roots.map({ $0.appending(path: browser.appName) }).first(where: { isApp($0, of: browser) }),
                  let data = try? Data(contentsOf: support.appending(path: browser.localState)) else { return nil }
            let profiles = profiles(localState: data, browser: browser)
            return profiles.isEmpty ? nil : InstalledBrowser(browser: browser, app: app, profiles: profiles)
        }
    }

    static func isApp(_ app: URL, of browser: ChromiumBrowser) -> Bool {
        OpenTarget.bundleIdentifier(of: app.path) == browser.bundleIdentifier
    }

    /// `open -na <app> --args --profile-directory=<id> [url]`: macOS starts the browser in that profile. Nil for a relative
    /// path, something that is not an app, or a folder id that is not one.
    public static func command(app: URL, directory: String, url: String?) -> Command? {
        let path = app.path
        guard path.hasPrefix("/"), path.hasSuffix(".app"), !path.contains("/../"), isValidDirectory(directory) else { return nil }
        if let url, url != connectorsURL { return nil }
        return Command(path: "/usr/bin/open", arguments: ["-na", path, "--args", "--profile-directory=\(directory)"] + (url.map { [$0] } ?? []))
    }

    /// The connectors page in the default browser, when no profile was picked.
    public static func defaultBrowserCommand(url: String) -> Command? {
        url == connectorsURL ? Command(path: "/usr/bin/open", arguments: [url]) : nil
    }

    /// `Local State`'s top level: only `profile`, then `info_cache`, then each profile's `name`.
    private struct StateRoot: Decodable {
        enum Key: String, CodingKey { case profile }
        enum ProfileKey: String, CodingKey { case infoCache = "info_cache" }
        let profiles: [(String, String?)]
        init(from decoder: Decoder) throws {
            let profile = try decoder.container(keyedBy: Key.self).nestedContainer(keyedBy: ProfileKey.self, forKey: .profile)
            let cache = try profile.nestedContainer(keyedBy: FolderKey.self, forKey: .infoCache)
            profiles = cache.allKeys.map { key in (key.stringValue, (try? cache.decode(Entry.self, forKey: key))?.name) }
        }
    }
    private struct FolderKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
    private struct Entry: Decodable {
        enum Key: String, CodingKey { case name }
        let name: String?
        init(from decoder: Decoder) throws {
            name = try? decoder.container(keyedBy: Key.self).decodeIfPresent(String.self, forKey: .name)
        }
    }
}
