import Foundation

/// One limit as Claude Code prints it for `/usage`: its name, the share used, and when it resets, in Claude Code's words.
public struct LimitLine: Equatable, Sendable {
    /// "Current session", "Current week (all models)", "Current week (Sonnet only)"...
    public let label: String
    public let percent: Double
    /// As Claude Code wrote it ("3pm (Europe/Zurich)"), nil when it gave none.
    public let resets: String?

    public init(label: String, percent: Double, resets: String?) {
        self.label = label; self.percent = percent; self.resets = resets
    }

    /// The share of a bar, from 0 to 1.
    public var fraction: Double { min(1, max(0, percent / 100)) }
}

/// "Check limits": on a click, and only then, Brainmerge asks the account's own official Claude Code what typing `/usage`
/// would show, `claude -p "/usage"`, and reads the text it prints. Brainmerge never reads limits by itself: no file of
/// Claude's, no login, no network of its own. Claude Code uses its own login, as whenever the person types /usage.
/// What it prints is kept in memory by the window, never written anywhere.
public enum ClaudeCodeLimits {
    /// `/usage` prints these lines as text from this version on.
    public static let minimumVersion = [2, 1, 275]
    /// How long Claude Code may take to answer, each time it is started.
    public static let timeout: TimeInterval = 20
    /// The system folders only: Claude Code is started by its absolute path and needs nothing else to answer /usage.
    public static let path = "/usr/bin:/bin:/usr/sbin:/sbin"

    // MARK: The text

    /// The limit lines of `/usage`, in order, each label once; any other line is passed over.
    public static func parse(_ output: String) -> [LimitLine] {
        // `Current session: 17% used · resets 3pm (Europe/Zurich)`, `Current week (<which>): …`; the reset may be missing.
        let linePattern = #/(Current (?:session|week \([^()]+\)))\s*:\s*(\d+(?:[.,]\d+)?)\s*%\s*used(?:\s*[·•|,-]?\s*[Rr]esets\s+(.+))?/#
        let plain = output.replacing(#/\x{1B}\[[0-9;?]*[A-Za-z]/#, with: "")
        var lines: [LimitLine] = []
        for raw in plain.split(whereSeparator: \.isNewline) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard let match = text.wholeMatch(of: linePattern) else { continue }
            let label = String(match.output.1)
            guard !lines.contains(where: { $0.label == label }),
                  let percent = Double(match.output.2.replacingOccurrences(of: ",", with: ".")) else { continue }
            let resets = match.output.3.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            lines.append(LimitLine(label: label, percent: percent, resets: resets))
        }
        return lines
    }

    /// Whether `claude --version` names a version that prints `/usage` as text.
    public static func isSupported(versionOutput: String) -> Bool {
        guard let match = versionOutput.firstMatch(of: #/(\d+)\.(\d+)\.(\d+)/#),
              let major = Int(match.output.1), let minor = Int(match.output.2), let patch = Int(match.output.3) else { return false }
        return [major, minor, patch].lexicographicallyPrecedes(minimumVersion) == false
    }

    // MARK: How it is asked

    /// Everything Claude Code is given: where home is, the system folders, and the account's Claude Code folder when it
    /// is not the default one. Nothing of Brainmerge's own environment, which can hold keys.
    public static func environment(home: URL, configDir: URL?) -> [String: String] {
        var environment = ["HOME": home.path, "PATH": path]
        if let configDir { environment["CLAUDE_CONFIG_DIR"] = configDir.path }
        return environment
    }

    /// The account's Claude Code folder, or nil for `~/.claude`: Claude Code runs there without CLAUDE_CONFIG_DIR, and
    /// setting it to `~/.claude` would make it use another `.claude.json` and another login.
    public static func configDir(of identity: Identity, paths: Paths) -> URL? {
        let profile = identity.cliProfile(in: paths)
        let isDefault = profile.standardizedFileURL.resolvingSymlinksInPath().path
            == paths.primaryCLIProfile.standardizedFileURL.resolvingSymlinksInPath().path
        return isDefault ? nil : profile
    }

    /// One start of Claude Code.
    public struct Invocation: Equatable, Sendable {
        public let executable: String
        public let arguments: [String]
        public let directory: URL
        public let environment: [String: String]
        public let timeout: TimeInterval
        public init(executable: String, arguments: [String], directory: URL, environment: [String: String], timeout: TimeInterval) {
            self.executable = executable; self.arguments = arguments; self.directory = directory
            self.environment = environment; self.timeout = timeout
        }
    }

    /// Starts Claude Code: Brainmerge's one process runner, with exactly the environment given; a fake in tests.
    public typealias Runner = @Sendable (Invocation) throws -> ShellResult
    public static let shell: Runner = { invocation in
        try Shell().runIsolated(invocation.executable, invocation.arguments, cwd: invocation.directory,
                                environment: invocation.environment, timeout: invocation.timeout)
    }

    /// What a click found out.
    public enum Outcome: Equatable, Sendable {
        case limits([LimitLine])
        case notFound
        /// Where it was found, home written `~`.
        case notSigned(String)
        case outdated
        case noAnswer

        /// Why there are no limits to show, or nil when there are.
        public var sentence: String? {
            switch self {
            case .limits: nil
            case .notFound: "Brainmerge did not find Claude Code in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin."
            case .notSigned(let path): "The Claude Code at \(path) is not signed by Anthropic, so Brainmerge will not run it."
            case .outdated: "Update Claude Code to check limits from here."
            case .noAnswer: "Claude Code did not return this account's limits."
            }
        }
    }

    /// Asks Claude Code its version, then, if it is recent enough, `/usage` for this account. Runs nothing without a
    /// Claude Code Anthropic signed. Blocks for up to twice `timeout`: call it off the main thread.
    public static func check(home: URL, configDir: URL?, binary: ClaudeCodeBinary.Resolution, run: Runner) -> Outcome {
        let executable: String
        switch binary {
        case .notFound: return .notFound
        case .notSigned(let path):
            let home = home.path
            return .notSigned(path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        case .found(let path): executable = path
        }
        let environment = environment(home: home, configDir: configDir)
        func ask(_ arguments: [String]) -> ShellResult? {
            let invocation = Invocation(executable: executable, arguments: arguments, directory: home, environment: environment, timeout: timeout)
            guard let result = try? run(invocation), result.status == 0 else { return nil }
            return result
        }
        guard let version = ask(["--version"]) else { return .noAnswer }
        guard isSupported(versionOutput: version.stdout) else { return .outdated }
        guard let usage = ask(["-p", "/usage"]) else { return .noAnswer }
        let lines = parse(usage.stdout)
        return lines.isEmpty ? .noAnswer : .limits(lines)
    }
}
