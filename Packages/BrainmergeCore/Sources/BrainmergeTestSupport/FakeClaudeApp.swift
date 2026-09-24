import Foundation
import BrainmergeCore

public enum FakeClaudeApp {
    /// A fake Claude.app: realistic plist, icon, binary = a script that logs its environment and arguments.
    @discardableResult
    public static func make(in directory: URL, version: String = "2.7032.0") throws -> ClaudeApp {
        let app = directory.appending(path: "Claude.app", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try Plist.write([
            "CFBundleIdentifier": ClaudeApp.bundleIdentifier,
            "CFBundleName": "Claude",
            "CFBundleDisplayName": "Claude",
            "CFBundleExecutable": "Claude",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleIconName": "Claude",
            "CFBundleIconFile": "electron",
        ], to: app.appending(path: "Contents/Info.plist"))
        let script = """
        #!/bin/sh
        printf 'CLAUDE_CONFIG_DIR=%s\\nARGS=%s\\n' "$CLAUDE_CONFIG_DIR" "$*" > "${BRAINMERGE_FAKE_LOG:-/dev/null}"
        """
        let exe = app.appending(path: "Contents/MacOS/Claude")
        try Data(script.utf8).write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try FakeIcon.writeICNS(to: app.appending(path: "Contents/Resources/electron.icns"))
        return try ClaudeApp.detect(at: app)
    }
}
