import Foundation

public struct Paths: Sendable, Equatable {
    public let home: URL

    public init(home: URL) { self.home = home.standardizedFileURL }

    /// The real HOME, or the one forced by BRAINMERGE_HOME (tests and scripts).
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> Paths {
        if let override = environment["BRAINMERGE_HOME"], !override.isEmpty {
            return Paths(home: URL(fileURLWithPath: override, isDirectory: true))
        }
        return Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var appSupport: URL { home.appending(path: "Library/Application Support/Brainmerge", directoryHint: .isDirectory) }
    public var stateFile: URL { appSupport.appending(path: "state.json") }
    public var iconsDir: URL { appSupport.appending(path: "icons", directoryHint: .isDirectory) }
    public var logsDir: URL { home.appending(path: "Library/Logs/Brainmerge", directoryHint: .isDirectory) }
    public var launchersDir: URL { home.appending(path: "Applications/Brainmerge", directoryHint: .isDirectory) }
    public var defaultBrain: URL { home.appending(path: "Brain", directoryHint: .isDirectory) }
    public var localBin: URL { home.appending(path: ".local/bin", directoryHint: .isDirectory) }
    public var primaryCLIProfile: URL { home.appending(path: ".claude", directoryHint: .isDirectory) }
    public var primaryDesktopData: URL { home.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory) }

    public func cliProfile(slug: String, isPrimary: Bool) -> URL {
        isPrimary ? primaryCLIProfile : home.appending(path: ".claude-\(slug)", directoryHint: .isDirectory)
    }
    public func desktopData(slug: String, isPrimary: Bool) -> URL {
        isPrimary ? primaryDesktopData : home.appending(path: "Library/Application Support/Claude-\(slug)", directoryHint: .isDirectory)
    }
    public func launcherApp(name: String) -> URL { launchersDir.appending(path: "\(name).app", directoryHint: .isDirectory) }
    public func tintedClone(name: String) -> URL { launchersDir.appending(path: "\(name) (Claude).app", directoryHint: .isDirectory) }
}
