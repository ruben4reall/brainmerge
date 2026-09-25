import Foundation
import LauncherGuard

// The wrapper copied into every launcher app: reads brainmerge.json next to itself, then either
// - exports CLAUDE_CONFIG_DIR and replaces its own process with the installed Claude on the account's folders, or
// - for the primary account's own app, asks macOS to open Claude itself (`open -a`), on Claude's own folders.
struct LauncherConfig: Decodable {
    let configDir: String?
    let dataDir: String?
    let claudeExecutable: String?
    let openApp: String?
}

let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
let configURL = contents.appending(path: "Resources/brainmerge.json")

guard let data = try? Data(contentsOf: configURL),
      let config = try? JSONDecoder().decode(LauncherConfig.self, from: data) else {
    FileHandle.standardError.write(Data("brainmerge launcher: missing or invalid \(configURL.path)\n".utf8))
    exit(2)
}

func refuse(_ sentence: String) -> Never {
    FileHandle.standardError.write(Data("brainmerge launcher: \(sentence)\n".utf8))
    exit(3)
}

func exec(_ path: String, _ arguments: [String]) -> Never {
    let cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    execv(path, cArguments)
    let reason = String(cString: strerror(errno))
    FileHandle.standardError.write(Data("brainmerge launcher: cannot start \(path): \(reason)\n".utf8))
    exit(1)
}

// The primary account's own app opens Anthropic's Claude at the path pinned in its Info.plist, and nothing else:
// no folder, no Claude Code profile, no argument, so Claude opens (or comes to the front) exactly as from Finder.
if let app = config.openApp {
    guard config.configDir == nil, config.dataDir == nil, config.claudeExecutable == nil else {
        refuse("this app only opens Claude; refusing folders next to \(app)")
    }
    let info = (try? Data(contentsOf: contents.appending(path: "Info.plist")))
        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    if let refusal = OpenTarget.refusal(openApp: app, pinned: info?[OpenTarget.pinKey] as? String) {
        refuse("this app only opens Claude; refusing \(app): \(refusal.reason)")
    }
    unsetenv("CLAUDE_CONFIG_DIR")
    exec("/usr/bin/open", ["open", "-a", app])
}

// This launcher starts Claude and nothing else: the executable must be a Claude binary inside an app bundle,
// and the folders must be absolute. A rewritten config cannot turn it into a launcher for another program.
guard let claude = config.claudeExecutable, let configDir = config.configDir, let dataDir = config.dataDir,
      claude.hasPrefix("/"), claude.hasSuffix("/Contents/MacOS/Claude") || claude.hasSuffix("/Contents/MacOS/Claude-bin"),
      configDir.hasPrefix("/"), dataDir.hasPrefix("/"),
      !configDir.contains("/../"), !dataDir.contains("/../"), !claude.contains("/../") else {
    refuse("this launcher only starts Claude; refusing \(config.claudeExecutable ?? "nothing") with \(config.configDir ?? "no folder") and \(config.dataDir ?? "no folder")")
}

setenv("CLAUDE_CONFIG_DIR", configDir, 1)
exec(claude, [claude, "--user-data-dir=\(dataDir)"] + CommandLine.arguments.dropFirst())
