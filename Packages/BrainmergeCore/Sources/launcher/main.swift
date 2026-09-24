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

setenv("CLAUDE_CONFIG_DIR", config.configDir, 1)
let arguments = [config.claudeExecutable, "--user-data-dir=\(config.dataDir)"] + CommandLine.arguments.dropFirst()
let cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
execv(config.claudeExecutable, cArguments)
let reason = String(cString: strerror(errno))
FileHandle.standardError.write(Data("brainmerge launcher: cannot start \(config.claudeExecutable): \(reason)\n".utf8))
exit(1)
