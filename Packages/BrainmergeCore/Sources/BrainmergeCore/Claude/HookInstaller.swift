import Foundation

/// Installs and removes the Stop hook `brainmerge sync` without touching other hooks or other settings.
public enum HookInstaller {
    /// The command path is quoted: the hook is recognized by `brainmerge` and this marker.
    public static let marker = "sync --identity"

    public static func isSyncHook(_ command: String) -> Bool {
        command.contains("brainmerge") && command.contains(marker)
    }

    public static func syncCommand(cliPath: String, slug: String) -> String {
        "\"\(cliPath)\" sync --identity \(slug)"
    }

    public static func isInstalled(settingsFile: URL) throws -> Bool {
        stopCommands(try readSettings(settingsFile)).contains(where: isSyncHook)
    }

    public static func install(settingsFile: URL, command: String) throws {
        var root = try readSettings(settingsFile)
        if stopCommands(root).contains(where: isSyncHook) { return }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stop = hooks["Stop"] as? [[String: Any]] ?? []
        stop.append(["hooks": [["type": "command", "command": command]]])
        hooks["Stop"] = stop
        root["hooks"] = hooks
        try writeSettings(root, to: settingsFile)
    }

    public static func remove(settingsFile: URL) throws {
        var root = try readSettings(settingsFile)
        guard var hooks = root["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]] else { return }
        let kept: [[String: Any]] = stop.compactMap { entry in
            var e = entry
            let inner = (e["hooks"] as? [[String: Any]] ?? [])
                .filter { !isSyncHook(($0["command"] as? String) ?? "") }
            if inner.isEmpty { return nil }
            e["hooks"] = inner
            return e
        }
        if kept.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = kept }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeSettings(root, to: settingsFile)
    }

    static func stopCommands(_ root: [String: Any]) -> [String] {
        let stop = (root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        return stop.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrainmergeError.invalidJSON(url.path)
        }
        return obj
    }

    static func writeSettings(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // Write to the target of a link, if any: an atomic write would replace the link with a file.
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }
}
