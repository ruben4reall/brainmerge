import Foundation
import BrainmergeCore

/// An app made by hand, like the owner's "Claude Second": a bundle whose executable is a launch script (or any bytes).
/// Test fixtures only: nothing ever runs them.
public enum HandMadeApp {
    /// The launch script of the owner's hand-made copy, byte for byte.
    public static let ownersScript = #"""
    #!/bin/bash
    export CLAUDE_CONFIG_DIR="$HOME/.claude-second"; exec "$(dirname "$0")/Claude-bin" --user-data-dir="$HOME/Library/Application Support/Claude-Second" "$@"
    """#

    /// `folder/<name>.app`: Claude's Info.plist keys, an executable made of `executable`, and (for a copy) Claude's frameworks folder.
    @discardableResult
    public static func make(_ name: String, in folder: URL, executable: Data, bundleID: String = ClaudeApp.bundleIdentifier,
                            version: String = "2.2553.13", frameworks: Bool = true) throws -> URL {
        let app = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        if frameworks {
            try fm.createDirectory(at: app.appending(path: "Contents/Frameworks/Electron Framework.framework"), withIntermediateDirectories: true)
        }
        try Plist.write(["CFBundleIdentifier": bundleID, "CFBundleName": "Claude", "CFBundleExecutable": "Claude",
                         "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"],
                        to: app.appending(path: "Contents/Info.plist"))
        let exe = app.appending(path: "Contents/MacOS/Claude")
        try executable.write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00]).write(to: app.appending(path: "Contents/MacOS/Claude-bin"))
        return app
    }

    @discardableResult
    public static func make(_ name: String, in folder: URL, script: String, bundleID: String = ClaudeApp.bundleIdentifier,
                            version: String = "2.2553.13", frameworks: Bool = true) throws -> URL {
        try make(name, in: folder, executable: Data(script.utf8), bundleID: bundleID, version: version, frameworks: frameworks)
    }
}
