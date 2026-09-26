import Foundation

/// The "distinct icon" option: a local APFS copy of Claude.app, tinted, whose main executable
/// is the wrapper. Must be rebuilt after every Claude update. Never distributed.
public struct TintedCloneBuilder: Sendable {
    public let paths: Paths
    public let launcherBinary: URL
    public let shell: Shell

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public init(paths: Paths, launcherBinary: URL, shell: Shell = Shell()) {
        self.paths = paths; self.launcherBinary = launcherBinary; self.shell = shell
    }

    @discardableResult
    public func build(for identity: Identity, claude: ClaudeApp, icon: URL, register: Bool = true) throws -> URL {
        let fm = FileManager.default
        // A signed Claude whose signature no longer matches its files is never copied: it is not Claude any more.
        // "Signed" means the bundle itself carries a signature that seals its resources; an executable signed only
        // by the linker, inside an unsigned bundle, is not a broken signature.
        let description = try shell.run("/usr/bin/codesign", ["-dv", claude.url.path])
        if description.status == 0, description.stderr.contains("Sealed Resources version="), !description.stderr.contains("linker-signed"),
           try shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", claude.url.path]).status != 0 {
            throw BrainmergeError.claudeAppTampered(claude.url.path)
        }
        let final = paths.tintedClone(name: identity.bundleDisplayName)
        try fm.createDirectory(at: paths.launchersDir, withIntermediateDirectories: true)
        // Built beside the old copy, which is replaced only once the new one is complete: a failure leaves the account its app.
        let app = BundleSwap.staging(for: final)
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        do {
            // cp -c: instant APFS clone. Outside APFS, cp refuses and we do a real copy.
            if try shell.run("/bin/cp", ["-Rc", claude.url.path, app.path]).status != 0 {
                try? fm.removeItem(at: app)
                try shell.check("/bin/cp", ["-R", claude.url.path, app.path])
            }

            let macos = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
            let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            let realBinary = macos.appending(path: "Claude-bin")
            try fm.moveItem(at: macos.appending(path: "Claude"), to: realBinary)
            try fm.copyItem(at: launcherBinary, to: macos.appending(path: "Claude"))
            let config = LauncherConfig(configDir: identity.cliProfile(in: paths).path,
                                        dataDir: identity.desktopData(in: paths).path,
                                        // Where the binary will be once the new copy is swapped in, not where it is built.
                                        claudeExecutable: final.appending(path: "Contents/MacOS/Claude-bin").path)
            try JSONEncoder().encode(config).write(to: resources.appending(path: "brainmerge.json"), options: .atomic)

            let iconTarget = resources.appending(path: "electron.icns")
            if fm.fileExists(atPath: iconTarget.path) { try fm.removeItem(at: iconTarget) }
            try fm.copyItem(at: icon, to: iconTarget)

            // macOS prefers CFBundleIconName (Assets.car) over electron.icns: without removing it, the Dock keeps the orange icon.
            let plistURL = app.appending(path: "Contents/Info.plist")
            var plist = try Plist.read(plistURL)
            plist.removeValue(forKey: "CFBundleIconName")
            try Plist.write(plist, to: plistURL)

            try shell.check("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            try BundleSwap.install(app, at: final)
        } catch {
            try? fm.removeItem(at: app)
            throw error
        }
        if register { _ = try? shell.run(Self.lsregister, ["-f", final.path]) }
        return final
    }
}

/// Builds a bundle next to the one it replaces (`<Name>.app.building`), then swaps it in.
enum BundleSwap {
    static func staging(for app: URL) -> URL {
        app.deletingLastPathComponent().appending(path: app.lastPathComponent + ".building", directoryHint: .isDirectory)
    }

    static func install(_ staging: URL, at app: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: app.path) {
            _ = try fm.replaceItemAt(app, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: app)
        }
    }
}
