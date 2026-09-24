import Darwin
import Foundation

/// Points `~/.local/bin/brainmerge` at the given executable. Idempotent.
public enum CLIInstaller {
    /// Name of the command-line tool embedded in the app. Not "brainmerge": next to "Brainmerge"
    /// in Contents/MacOS, the two names collide on a case-insensitive disk.
    public static let embeddedExecutableName = "brainmerge-cli"

    public static func link(in paths: Paths) -> URL { paths.localBin.appending(path: "brainmerge") }

    /// The current executable, asked from the kernel. `Bundle.main.executableURL` points to the app when
    /// the command-line tool lives inside its bundle: it doesn't apply here.
    public static func currentExecutable() -> URL? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }

    /// Volume mounted read-only (disk image, sealed system volume). `URLResourceValues.volumeIsReadOnly`
    /// returns false for the system volume: we read the mount flags instead.
    public static func isOnReadOnlyVolume(_ path: String) -> Bool {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return false }
        return (info.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    /// The command-line tool embedded next to an executable, under its exact name, or nil.
    public static func embeddedCLI(besideExecutable exe: URL) -> URL? {
        let dir = exe.resolvingSymlinksInPath().deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              names.contains(embeddedExecutableName) else { return nil }
        return dir.appending(path: embeddedExecutableName)
    }

    /// Creates the link. A valid link to another binary is kept unless `replaceValid` (the "Install command line" button
    /// and `install-cli`): a development build doesn't hijack the link that every hook calls.
    /// A regular file at this location is never deleted. A target on a read-only volume (disk image) is refused.
    public static func ensureLink(paths: Paths, target: URL, replaceValid: Bool = false) throws {
        let fm = FileManager.default
        let link = link(in: paths)
        let resolved = target.resolvingSymlinksInPath()
        if isOnReadOnlyVolume(resolved.path) { throw BrainmergeError.cliOnReadOnlyVolume(resolved.path) }
        try fm.createDirectory(at: paths.localBin, withIntermediateDirectories: true)
        if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if existing == resolved.path { return }
            if !replaceValid, fm.isExecutableFile(atPath: existing) { return }
            try fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            throw BrainmergeError.cliLinkOccupied(link.path)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: resolved)
    }
}
