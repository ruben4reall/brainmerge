import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// "Check limits": the text Claude Code prints for `/usage`, read line by line, and how it is asked. A fake runner
/// stands in for Claude Code: the real one is never run here.
@Suite struct ClaudeCodeLimitsTests {
    static let full = """
    Current session: 17% used · resets 3pm (Europe/Zurich)
    Current week (all models): 42% used · resets Oct 2, 9am (Europe/Zurich)
    Current week (Sonnet only): 5% used · resets Oct 2, 9am (Europe/Zurich)
    Current week (Opus): 0% used
    """

    // MARK: The text

    @Test func readsEveryLine() {
        #expect(ClaudeCodeLimits.parse(Self.full) == [
            LimitLine(label: "Current session", percent: 17, resets: "3pm (Europe/Zurich)"),
            LimitLine(label: "Current week (all models)", percent: 42, resets: "Oct 2, 9am (Europe/Zurich)"),
            LimitLine(label: "Current week (Sonnet only)", percent: 5, resets: "Oct 2, 9am (Europe/Zurich)"),
            LimitLine(label: "Current week (Opus)", percent: 0, resets: nil),
        ])
    }

    @Test func keepsTheLinesThatAreThere() {
        let output = "Current week (all models): 64% used · resets Sep 30, 8am (America/New_York)\n"
        #expect(ClaudeCodeLimits.parse(output) == [LimitLine(label: "Current week (all models)", percent: 64, resets: "Sep 30, 8am (America/New_York)")])
    }

    /// Headers, blank lines, colors, Windows line ends and lines about anything else are passed over.
    @Test func passesOverEverythingElse() {
        let output = "\u{1B}[1mUsage\u{1B}[0m\r\n\r\n  Current session: \u{1B}[32m9% used\u{1B}[0m · resets 11pm (Europe/Paris)\r\n"
            + "Extra usage: not enabled\r\nCurrent month: 12% used\r\nCurrent session used\r\nPlan: Max\r\n"
        #expect(ClaudeCodeLimits.parse(output) == [LimitLine(label: "Current session", percent: 9, resets: "11pm (Europe/Paris)")])
    }

    /// The reset time is Claude Code's own text, whatever language or format it comes in.
    @Test func keepsTheResetTimeAsWritten() {
        let output = """
        Current session: 3% used · resets 15:00 (Europe/Paris)
        Current week (all models): 12.5% used · resets 2 oct., 09:00 (Europe/Paris)
        Current week (Sonnet only): 7% used · Resets Oct 2 at 9:00 AM
        """
        #expect(ClaudeCodeLimits.parse(output) == [
            LimitLine(label: "Current session", percent: 3, resets: "15:00 (Europe/Paris)"),
            LimitLine(label: "Current week (all models)", percent: 12.5, resets: "2 oct., 09:00 (Europe/Paris)"),
            LimitLine(label: "Current week (Sonnet only)", percent: 7, resets: "Oct 2 at 9:00 AM"),
        ])
    }

    @Test func somethingElseIsNoLimits() {
        for output in ["", "Invalid API key · Please run /login", #"{"type":"result","result":"Current session"}"#,
                       "Unknown slash command: usage", "Current session: a lot"] {
            #expect(ClaudeCodeLimits.parse(output).isEmpty, "\(output)")
        }
    }

    @Test func aLineIsReadOnce() {
        let output = "Current session: 17% used · resets 3pm\nCurrent session: 18% used · resets 3pm\n"
        #expect(ClaudeCodeLimits.parse(output) == [LimitLine(label: "Current session", percent: 17, resets: "3pm")])
    }

    @Test func theBarStaysWithinItsTrack() {
        #expect(LimitLine(label: "Current session", percent: 42, resets: nil).fraction == 0.42)
        #expect(LimitLine(label: "Current session", percent: 130, resets: nil).fraction == 1)
    }

    // MARK: The version

    @Test func needsClaudeCode2_1_275OrLater() {
        for output in ["2.1.275 (Claude Code)", "2.1.280 (Claude Code)\n", "2.2.0 (Claude Code)", "10.0.0", "3.0.0-beta.1"] {
            #expect(ClaudeCodeLimits.isSupported(versionOutput: output), "\(output)")
        }
        for output in ["2.1.274 (Claude Code)", "1.9.999", "2.0.300", "Claude Code", "", "2.1"] {
            #expect(!ClaudeCodeLimits.isSupported(versionOutput: output), "\(output)")
        }
    }

    // MARK: How it is asked

    @Test func onlyWhatClaudeCodeNeedsIsPassed() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(ClaudeCodeLimits.environment(home: home, configDir: nil) == ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let profile = URL(fileURLWithPath: "/Users/someone/.claude-client", isDirectory: true)
        #expect(ClaudeCodeLimits.environment(home: home, configDir: profile)
                == ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "CLAUDE_CONFIG_DIR": "/Users/someone/.claude-client"])
    }

    /// `~/.claude` is Claude Code without CLAUDE_CONFIG_DIR: setting it to `~/.claude` would read another `.claude.json`.
    @Test func theDefaultProfileRunsWithoutAConfigFolder() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/someone", isDirectory: true))
        let primary = Identity(slug: "ruben", name: "Ruben", isPrimary: true)
        let client = Identity(slug: "client", name: "Client")
        let codeOnly = Identity(slug: "code", name: "Code", surfaces: Surfaces(desktop: false, cli: true))
        let adopted = Identity(slug: "old", name: "Old", cliProfilePath: "/Users/someone/.claude")
        #expect(ClaudeCodeLimits.configDir(of: primary, paths: paths) == nil)
        #expect(ClaudeCodeLimits.configDir(of: client, paths: paths)?.path == "/Users/someone/.claude-client")
        #expect(ClaudeCodeLimits.configDir(of: codeOnly, paths: paths)?.path == "/Users/someone/.claude-code")
        #expect(ClaudeCodeLimits.configDir(of: adopted, paths: paths) == nil)
    }

    /// The runner the app uses hands over exactly the invocation's variables: Brainmerge's own environment (an API key,
    /// a token, another account's CLAUDE_CONFIG_DIR) never reaches Claude Code. A system program stands in for it.
    @Test(.timeLimit(.minutes(1))) func theAppsRunnerPassesOnlyTheseVariables() throws {
        let home = try TempHome(); defer { home.remove() }
        let invocation = ClaudeCodeLimits.Invocation(executable: "/usr/bin/env", arguments: [], directory: home.url,
                                                     environment: ["HOME": home.url.path, "PATH": ClaudeCodeLimits.path], timeout: 10)
        let result = try ClaudeCodeLimits.shell(invocation)
        #expect(result.status == 0)
        #expect(Set(result.stdout.split(separator: "\n").map(String.init))
                == ["HOME=\(home.url.path)", "PATH=/usr/bin:/bin:/usr/sbin:/sbin"], "\(result.stdout)")
    }

    /// Stands in for Claude Code: records each run and answers from `answers`, by first argument.
    final class FakeClaudeCode: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClaudeCodeLimits.Invocation] = []
        let answers: [String: Result<ShellResult, BrainmergeError>]
        init(version: Result<ShellResult, BrainmergeError> = .success(ShellResult(status: 0, stdout: "2.1.280 (Claude Code)\n", stderr: "")),
             usage: Result<ShellResult, BrainmergeError> = .success(ShellResult(status: 0, stdout: ClaudeCodeLimitsTests.full, stderr: ""))) {
            answers = ["--version": version, "-p": usage]
        }
        var runs: [ClaudeCodeLimits.Invocation] { lock.lock(); defer { lock.unlock() }; return recorded }
        var run: ClaudeCodeLimits.Runner {
            { invocation in
                self.lock.lock(); self.recorded.append(invocation); self.lock.unlock()
                return try self.answers[invocation.arguments.first ?? ""]?.get() ?? ShellResult(status: 1, stdout: "", stderr: "")
            }
        }
    }

    static let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    static let client = URL(fileURLWithPath: "/Users/someone/.claude-client", isDirectory: true)
    static let binary = "/Users/someone/.local/share/claude/versions/2.1.280"

    @Test func asksTheVersionThenTheUsageOfThatAccount() {
        let fake = FakeClaudeCode()
        let outcome = ClaudeCodeLimits.check(home: Self.home, configDir: Self.client, binary: .found(Self.binary), run: fake.run)
        #expect(outcome == .limits(ClaudeCodeLimits.parse(Self.full)))
        let environment = ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "CLAUDE_CONFIG_DIR": "/Users/someone/.claude-client"]
        #expect(fake.runs == [
            ClaudeCodeLimits.Invocation(executable: Self.binary, arguments: ["--version"], directory: Self.home, environment: environment, timeout: 20),
            ClaudeCodeLimits.Invocation(executable: Self.binary, arguments: ["-p", "/usage"], directory: Self.home, environment: environment, timeout: 20),
        ])
    }

    @Test func anOlderClaudeCodeIsNotAskedForLimits() {
        let fake = FakeClaudeCode(version: .success(ShellResult(status: 0, stdout: "2.1.274 (Claude Code)\n", stderr: "")))
        let outcome = ClaudeCodeLimits.check(home: Self.home, configDir: nil, binary: .found(Self.binary), run: fake.run)
        #expect(outcome == .outdated)
        #expect(fake.runs.map(\.arguments) == [["--version"]])
    }

    @Test func anythingButTheLinesIsNoAnswer() {
        let answers: [(Result<ShellResult, BrainmergeError>, Result<ShellResult, BrainmergeError>)] = [
            (.success(ShellResult(status: 0, stdout: "2.1.280\n", stderr: "")), .success(ShellResult(status: 0, stdout: "Please run /login\n", stderr: ""))),
            (.success(ShellResult(status: 0, stdout: "2.1.280\n", stderr: "")), .success(ShellResult(status: 1, stdout: Self.full, stderr: "error"))),
            (.success(ShellResult(status: 0, stdout: "2.1.280\n", stderr: "")), .failure(.timedOut(command: "claude -p /usage"))),
            (.failure(.timedOut(command: "claude --version")), .success(ShellResult(status: 0, stdout: Self.full, stderr: ""))),
            (.success(ShellResult(status: 2, stdout: "", stderr: "")), .success(ShellResult(status: 0, stdout: Self.full, stderr: ""))),
        ]
        for (version, usage) in answers {
            let fake = FakeClaudeCode(version: version, usage: usage)
            #expect(ClaudeCodeLimits.check(home: Self.home, configDir: nil, binary: .found(Self.binary), run: fake.run) == .noAnswer)
        }
    }

    @Test func nothingRunsWithoutASignedClaudeCode() {
        let fake = FakeClaudeCode()
        #expect(ClaudeCodeLimits.check(home: Self.home, configDir: nil, binary: .notFound, run: fake.run) == .notFound)
        #expect(ClaudeCodeLimits.check(home: Self.home, configDir: nil, binary: .notSigned("/Users/someone/.local/bin/claude"), run: fake.run)
                == .notSigned("~/.local/bin/claude"))
        #expect(ClaudeCodeLimits.check(home: Self.home, configDir: nil, binary: .notSigned("/opt/homebrew/bin/claude"), run: fake.run)
                == .notSigned("/opt/homebrew/bin/claude"))
        #expect(fake.runs.isEmpty)
    }

    @Test func eachRefusalSaysWhatToDo() {
        #expect(ClaudeCodeLimits.Outcome.limits([]).sentence == nil)
        #expect(ClaudeCodeLimits.Outcome.notFound.sentence == "Brainmerge did not find Claude Code in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin.")
        #expect(ClaudeCodeLimits.Outcome.notSigned("/opt/homebrew/bin/claude").sentence
                == "The Claude Code at /opt/homebrew/bin/claude is not signed by Anthropic, so Brainmerge will not run it.")
        #expect(ClaudeCodeLimits.Outcome.outdated.sentence == "Update Claude Code to check limits from here.")
        #expect(ClaudeCodeLimits.Outcome.noAnswer.sentence == "Claude Code did not return this account's limits.")
    }
}
