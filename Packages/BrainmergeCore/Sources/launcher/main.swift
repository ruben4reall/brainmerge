import Foundation

// The wrapper copied into every launcher app: reads brainmerge.json next to itself,
// exports CLAUDE_CONFIG_DIR, and replaces its own process with the installed Claude.
struct LauncherConfig: Decodable {
    let configDir: String
    let dataDir: String
    let claudeExecutable: String
}

let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let configURL = executable.deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Resources/brainmerge.json")

guard let data = try? Data(contentsOf: configURL),
      let config = try? JSONDecoder().decode(LauncherConfig.self, from: data) else {
    FileHandle.standardError.write(Data("brainmerge launcher: missing or invalid \(configURL.path)\n".utf8))
    exit(2)
}

// This launcher starts Claude and nothing else: the executable must be a Claude binary inside an app bundle,
// and the folders must be absolute. A rewritten config cannot turn it into a launcher for another program.
let claudeBinary = config.claudeExecutable.hasSuffix("/Contents/MacOS/Claude") || config.claudeExecutable.hasSuffix("/Contents/MacOS/Claude-bin")
guard config.claudeExecutable.hasPrefix("/"), claudeBinary, config.configDir.hasPrefix("/"), config.dataDir.hasPrefix("/"),
      !config.configDir.contains("/../"), !config.dataDir.contains("/../"), !config.claudeExecutable.contains("/../") else {
    FileHandle.standardError.write(Data("brainmerge launcher: this launcher only starts Claude; refusing \(config.claudeExecutable) with \(config.configDir) and \(config.dataDir)\n".utf8))
    exit(3)
}

setenv("CLAUDE_CONFIG_DIR", config.configDir, 1)
let arguments = [config.claudeExecutable, "--user-data-dir=\(config.dataDir)"] + CommandLine.arguments.dropFirst()
let cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
execv(config.claudeExecutable, cArguments)
let reason = String(cString: strerror(errno))
FileHandle.standardError.write(Data("brainmerge launcher: cannot start \(config.claudeExecutable): \(reason)\n".utf8))
exit(1)
