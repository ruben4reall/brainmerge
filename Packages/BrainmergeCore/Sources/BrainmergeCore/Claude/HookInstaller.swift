import Foundation

/// Installs and removes Brainmerge's Claude Code hooks without touching other hooks or other settings.
public enum HookInstaller {
    /// The hook events Brainmerge uses. Each has its own marker, how its entry is recognized next to the command path.
    public enum Event: String, CaseIterable, Sendable {
        case stop = "Stop", sessionStart = "SessionStart", postToolUse = "PostToolUse"

        public var marker: String {
            switch self {
            case .stop: "sync --identity"
            case .sessionStart: "wire --identity"
            case .postToolUse: "touched --identity"
            }
        }
    }

    /// One hook as Brainmerge writes it.
    public struct Hook: Equatable, Sendable {
        public let event: Event
        public let command: String
        public let matcher: String?
        public let timeout: Int?
    }

    /// What an account's settings hold of Brainmerge's hooks.
    public enum Health: String, Sendable { case current, outdated, missing }

    /// The Stop hook's marker (kept for the callers that only know the Stop hook).
    public static let marker = Event.stop.marker

    public static func isHook(_ command: String, of event: Event) -> Bool {
        command.contains("brainmerge") && command.contains(event.marker)
    }

    /// Any of Brainmerge's hooks, whatever the event it sits under.
    public static func isBrainmergeHook(_ command: String) -> Bool { Event.allCases.contains { isHook(command, of: $0) } }

    public static func isSyncHook(_ command: String) -> Bool { isHook(command, of: .stop) }

    /// The command survives a missing binary (the app trashed or moved): nothing runs, and it still exits 0, so a
    /// session is never blocked and never shows a hook error.
    static func guarded(cliPath: String, _ arguments: String) -> String {
        let cli = quoted(cliPath)
        return "test -x \(cli) && \(cli) \(arguments); exit 0"
    }

    /// Double quotes, with the four characters the shell still reads inside them escaped: the path stays literal.
    static func quoted(_ path: String) -> String {
        var out = "\""
        for ch in path {
            if "\"$`\\".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out + "\""
    }

    public static func syncCommand(cliPath: String, slug: String) -> String {
        guarded(cliPath: cliPath, "sync --identity \(slug)")
    }

    public static func wireCommand(cliPath: String, slug: String) -> String {
        guarded(cliPath: cliPath, "wire --identity \(slug) --hook")
    }

    public static func touchedCommand(cliPath: String, slug: String) -> String {
        guarded(cliPath: cliPath, "touched --identity \(slug)")
    }

    /// The edit tools whose input names the file they wrote (`file_path`): what an account wrote is noted after each.
    public static let editTools = "Write|Edit|MultiEdit"

    /// The hooks an account gets: saving the memory when a turn ends, linking the project's memory when a session
    /// starts, and noting each file an edit wrote (so a save commits exactly what this account wrote). SessionStart and
    /// PostToolUse hold the session while they run, so they are bounded to 5 seconds.
    public static func expected(cliPath: String, slug: String) -> [Hook] {
        [Hook(event: .stop, command: syncCommand(cliPath: cliPath, slug: slug), matcher: nil, timeout: nil),
         Hook(event: .sessionStart, command: wireCommand(cliPath: cliPath, slug: slug), matcher: nil, timeout: 5),
         Hook(event: .postToolUse, command: touchedCommand(cliPath: cliPath, slug: slug), matcher: editTools, timeout: 5)]
    }

    public static func installAll(settingsFile: URL, cliPath: String, slug: String) throws {
        for hook in expected(cliPath: cliPath, slug: slug) {
            try install(settingsFile: settingsFile, event: hook.event, command: hook.command, matcher: hook.matcher, timeout: hook.timeout)
        }
    }

    public static func isInstalled(settingsFile: URL, event: Event = .stop) throws -> Bool {
        commands(try readSettings(settingsFile), event: event).contains { isHook($0, of: event) }
    }

    /// Current when each expected hook is there exactly once and exactly as written today; missing when none of
    /// Brainmerge's hooks is there (or the file cannot be read); outdated otherwise.
    public static func health(settingsFile: URL, cliPath: String, slug: String) -> Health {
        guard let root = try? readSettings(settingsFile) else { return .missing }
        guard Event.allCases.contains(where: { event in commands(root, event: event).contains(where: isBrainmergeHook) }) else { return .missing }
        for hook in expected(cliPath: cliPath, slug: slug) {
            let found = entries(root, event: hook.event).flatMap { entry in
                inner(entry).filter { isHook(($0["command"] as? String) ?? "", of: hook.event) }.map { (entry, $0) }
            }
            guard found.count == 1, let only = found.first, matches(only.1, entry: only.0, hook) else { return .outdated }
        }
        return .current
    }

    /// An upsert: Brainmerge's entry for this event, in any older format, is replaced where it stands, a second copy is
    /// dropped (it would run twice), and the person's hooks are never touched. Nothing is written when it is already right.
    public static func install(settingsFile: URL, event: Event = .stop, command: String, matcher: String? = nil, timeout: Int? = nil) throws {
        var root = try readSettings(settingsFile)
        let hook = Hook(event: event, command: command, matcher: matcher, timeout: timeout)
        var list = entries(root, event: event)
        let ours = list.enumerated().flatMap { index, entry in
            inner(entry).enumerated().filter { isHook(($0.element["command"] as? String) ?? "", of: event) }.map { (index, $0.offset) }
        }
        if ours.count == 1, let only = ours.first, matches(inner(list[only.0])[only.1], entry: list[only.0], hook) { return }

        var written: [String: Any] = ["type": "command", "command": command]
        if let timeout { written["timeout"] = timeout }
        // Where Brainmerge's first hook stands: replaced there when its entry is its own or its matcher is the right one.
        var placed = false
        var emptied: Set<Int> = []
        for (index, entry) in list.enumerated() {
            let hooks = inner(entry)
            let foreign = hooks.contains { !isHook(($0["command"] as? String) ?? "", of: event) }
            var kept: [[String: Any]] = []
            var placedHere = false
            for item in hooks {
                guard isHook((item["command"] as? String) ?? "", of: event) else { kept.append(item); continue }
                if !placed, !foreign || entry["matcher"] as? String == matcher {
                    kept.append(written)
                    placed = true
                    placedHere = true
                }
            }
            if kept.count == hooks.count, !placedHere { continue }
            var updated = entry
            updated["hooks"] = kept
            if placedHere, !foreign { if let matcher { updated["matcher"] = matcher } else { updated.removeValue(forKey: "matcher") } }
            list[index] = updated
            // An entry left with nothing once a second copy of Brainmerge's hook went; an empty one of the person's stays.
            if kept.isEmpty { emptied.insert(index) }
        }
        list = list.enumerated().filter { !emptied.contains($0.offset) }.map(\.element)
        if !placed {
            var entry: [String: Any] = ["hooks": [written]]
            if let matcher { entry["matcher"] = matcher }
            list.append(entry)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks[event.rawValue] = list
        root["hooks"] = hooks
        try writeSettings(root, to: settingsFile)
    }

    /// Clears every Brainmerge hook, under every event; the person's hooks stay.
    public static func remove(settingsFile: URL) throws {
        var root = try readSettings(settingsFile)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for event in Event.allCases {
            guard let list = hooks[event.rawValue] as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = list.compactMap { entry in
                var e = entry
                let rest = inner(entry).filter { !isBrainmergeHook(($0["command"] as? String) ?? "") }
                if rest.isEmpty { return nil }
                e["hooks"] = rest
                return e
            }
            if kept.isEmpty { hooks.removeValue(forKey: event.rawValue) } else { hooks[event.rawValue] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeSettings(root, to: settingsFile)
    }

    static func matches(_ inner: [String: Any], entry: [String: Any], _ hook: Hook) -> Bool {
        inner["command"] as? String == hook.command && inner["type"] as? String == "command"
            && inner["timeout"] as? Int == hook.timeout && (inner["timeout"] == nil) == (hook.timeout == nil)
            && entry["matcher"] as? String == hook.matcher && (entry["matcher"] == nil) == (hook.matcher == nil)
    }

    static func entries(_ root: [String: Any], event: Event) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?[event.rawValue] as? [[String: Any]] ?? []
    }

    static func inner(_ entry: [String: Any]) -> [[String: Any]] { entry["hooks"] as? [[String: Any]] ?? [] }

    static func commands(_ root: [String: Any], event: Event) -> [String] {
        entries(root, event: event).flatMap { inner($0).compactMap { $0["command"] as? String } }
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
