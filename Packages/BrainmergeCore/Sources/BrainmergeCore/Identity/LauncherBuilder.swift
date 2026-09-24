import Foundation

/// What the wrapper reads at launch (Contents/Resources/brainmerge.json).
public struct LauncherConfig: Codable, Equatable, Sendable {
    public var configDir: String
    public var dataDir: String
    public var claudeExecutable: String
    public init(configDir: String, dataDir: String, claudeExecutable: String) {
        self.configDir = configDir; self.dataDir = dataDir; self.claudeExecutable = claudeExecutable
    }
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

    /// `register: false` avoids registering the disposable test bundles with Launch Services.
    @discardableResult
    public func build(for identity: Identity, claude: ClaudeApp, icon: URL?, register: Bool = true) throws -> URL {
        let fm = FileManager.default
        let app = paths.launcherApp(name: identity.bundleDisplayName)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let macos = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.copyItem(at: launcherBinary, to: macos.appending(path: "launcher"))

        let config = LauncherConfig(configDir: identity.cliProfile(in: paths).path,
                                    dataDir: identity.desktopData(in: paths).path,
                                    claudeExecutable: claude.executable.path)
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
        if let icon {
            try fm.copyItem(at: icon, to: resources.appending(path: "icon.icns"))
            plist["CFBundleIconFile"] = "icon"
        }
        try Plist.write(plist, to: contents.appending(path: "Info.plist"))
        try shell.check("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        if register { _ = try? shell.run(Self.lsregister, ["-f", app.path]) }
        return app
    }
}
