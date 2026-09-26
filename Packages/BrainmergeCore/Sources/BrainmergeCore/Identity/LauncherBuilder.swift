import Foundation
import LauncherGuard

/// What the wrapper reads at launch (Contents/Resources/brainmerge.json): the folders and the Claude binary of a
/// secondary account, or, for the primary account's own app, only the Claude app to open.
public struct LauncherConfig: Codable, Equatable, Sendable {
    public var configDir: String?
    public var dataDir: String?
    public var claudeExecutable: String?
    /// The primary's own app: the Claude app it opens, on Claude's own folders. Nil for a secondary account.
    public var openApp: String?
    public init(configDir: String, dataDir: String, claudeExecutable: String) {
        self.configDir = configDir; self.dataDir = dataDir; self.claudeExecutable = claudeExecutable
    }
    public init(openApp: String) { self.openApp = openApp }
}

/// Builds `~/Applications/Brainmerge/<Name>.app`: a tiny, ad hoc signed bundle
/// whose executable is the `launcher` wrapper. Claude.app is never touched.
public struct LauncherBuilder: Sendable {
    public let paths: Paths
    public let launcherBinary: URL
    public let shell: Shell

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public init(paths: Paths, launcherBinary: URL, shell: Shell = Shell()) {
        self.paths = paths; self.launcherBinary = launcherBinary; self.shell = shell
    }

    /// The `launcher` binary lives next to the current executable (brainmerge, or Brainmerge.app/Contents/Helpers).
    public static func siblingLauncher() -> URL {
        let exe = CLIInstaller.currentExecutable() ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().appending(path: "launcher")
    }

    /// Whether the apps built for this home go into Launch Services: only for the real home. A home forced by
    /// BRAINMERGE_HOME is a test's or a demo's, thrown away with its apps; registering them would leave records under real
    /// accounts' identifiers long after their folder is gone.
    public static func registersApps(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        (environment["BRAINMERGE_HOME"] ?? "").isEmpty
    }

    /// `register: false` avoids registering the disposable test bundles with Launch Services.
    @discardableResult
    public func build(for identity: Identity, claude: ClaudeApp, icon: URL?, register: Bool = true) throws -> URL {
        let config = LauncherConfig(configDir: identity.cliProfile(in: paths).path,
                                    dataDir: identity.desktopData(in: paths).path,
                                    claudeExecutable: claude.executable.path)
        return try makeBundle(for: identity, config: config, plist: [:], icon: icon, register: register)
    }

    /// The primary account's own app: the same small bundle with the account's icon, whose launcher opens Claude itself
    /// (`open -a`) on its own folders. Claude's path is pinned in the Info.plist as well: the launcher opens nothing else,
    /// and only when Anthropic signed it (see OpenTarget). No Dock tile of its own while it hands over (LSUIElement).
    @discardableResult
    public func buildOpener(for identity: Identity, claude: ClaudeApp, icon: URL?, register: Bool = true) throws -> URL {
        try makeBundle(for: identity, config: LauncherConfig(openApp: claude.url.path),
                       plist: [OpenTarget.pinKey: claude.url.path, "LSUIElement": true], icon: icon, register: register)
    }

    func makeBundle(for identity: Identity, config: LauncherConfig, plist extra: [String: Any], icon: URL?, register: Bool) throws -> URL {
        let fm = FileManager.default
        let final = paths.launcherApp(name: identity.bundleDisplayName)
        // Built beside the old app and swapped in once complete: a failure leaves the account its app.
        let app = BundleSwap.staging(for: final)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let macos = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        do {
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try fm.copyItem(at: launcherBinary, to: macos.appending(path: "launcher"))
            try JSONEncoder().encode(config).write(to: resources.appending(path: "brainmerge.json"), options: .atomic)

            var plist: [String: Any] = [
                "CFBundleIdentifier": "ch.rubencatalao.brainmerge.launch.\(identity.slug)",
                "CFBundleName": identity.bundleDisplayName,
                "CFBundleDisplayName": identity.bundleDisplayName,
                "CFBundleExecutable": "launcher",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "13.0",
                "NSHighResolutionCapable": true,
            ]
            plist.merge(extra) { _, new in new }
            if let icon {
                try fm.copyItem(at: icon, to: resources.appending(path: "icon.icns"))
                plist["CFBundleIconFile"] = "icon"
            }
            try Plist.write(plist, to: contents.appending(path: "Info.plist"))
            try shell.check("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
            try BundleSwap.install(app, at: final)
        } catch {
            try? fm.removeItem(at: app)
            throw error
        }
        if register { _ = try? shell.run(Self.lsregister, ["-f", final.path]) }
        return final
    }
}
