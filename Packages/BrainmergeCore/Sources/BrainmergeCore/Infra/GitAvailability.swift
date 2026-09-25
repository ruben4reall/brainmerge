import Foundation

/// Whether git can run without macOS popping Apple's "install the command line developer tools" dialog. On a clean Mac
/// `/usr/bin/git` is only a stub that shows that dialog and fails, so it is never started before this says yes.
/// The answer is kept until `invalidate()` ("Check again"): the graph asks for the history every few seconds.
public final class GitAvailability: @unchecked Sendable {
    public static let shared = GitAvailability()

    private let shell: Shell
    private let isExecutable: @Sendable (String) -> Bool
    private let lock = NSLock()
    private var cached: Bool?

    public init(shell: Shell = Shell(),
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.shell = shell; self.isExecutable = isExecutable
    }

    /// `xcode-select -p` names the developer folder (it never shows a dialog), and that folder has git.
    public var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        var found = false
        if let result = try? shell.run("/usr/bin/xcode-select", ["-p"]), result.status == 0 {
            let folder = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            found = !folder.isEmpty && isExecutable(folder + "/usr/bin/git")
        }
        cached = found
        return found
    }

    public func invalidate() { lock.lock(); cached = nil; lock.unlock() }

    /// Starts Apple's own installer for the Command Line Tools. The download comes from Apple.
    public func install() throws {
        _ = try shell.run("/usr/bin/xcode-select", ["--install"])
        invalidate()
    }
}
