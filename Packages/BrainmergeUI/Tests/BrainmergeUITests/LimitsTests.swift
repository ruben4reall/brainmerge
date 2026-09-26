import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// "Check limits" on the Usage screen: only a click asks, it asks that account's own Claude Code, and what comes back
/// stays in memory. A fake stands in for Claude Code; the real one is never looked for or run here.
@MainActor @Suite struct LimitsTests {
    nonisolated static let usage = """
    Current session: 17% used · resets 3pm (Test/Zone)
    Current week (all models): 42% used · resets Oct 2, 9am (Test/Zone)
    """
    static let lines = [LimitLine(label: "Current session", percent: 17, resets: "3pm (Test/Zone)"),
                        LimitLine(label: "Current week (all models)", percent: 42, resets: "Oct 2, 9am (Test/Zone)")]

    /// Holds every Claude Code start back until opened, then lets all of them through, however many there are.
    final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var isOpen = false
        func wait() { condition.lock(); while !isOpen { condition.wait() }; condition.unlock() }
        func open() { condition.lock(); isOpen = true; condition.broadcast(); condition.unlock() }
    }

    /// Stands in for Claude Code: records every start, answers `--version` and `/usage`, and can hold an answer back.
    final class FakeClaudeCode: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClaudeCodeLimits.Invocation] = []
        private var lookups = 0
        let version: String
        let gate: Gate?
        init(version: String = "2.1.280 (Claude Code)\n", gate: Gate? = nil) { self.version = version; self.gate = gate }
        var runs: [ClaudeCodeLimits.Invocation] { lock.lock(); defer { lock.unlock() }; return recorded }
        var binaryLookups: Int { lock.lock(); defer { lock.unlock() }; return lookups }

        @MainActor func install(in model: AppModel, binary: ClaudeCodeBinary.Resolution = .found("/fake/claude")) {
            model.limitsBinary = { _ in self.lock.lock(); self.lookups += 1; self.lock.unlock(); return binary }
            model.limitsRunner = { invocation in
                self.lock.lock(); self.recorded.append(invocation); self.lock.unlock()
                self.gate?.wait()
                let out = invocation.arguments == ["--version"] ? self.version : LimitsTests.usage
                return ShellResult(status: 0, stdout: out, stderr: "")
            }
        }
    }

    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.environment = [:]
        return model
    }

    func setUp() throws -> (ManagerEnv, AppModel, FakeClaudeCode) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        let fake = FakeClaudeCode()
        fake.install(in: m)
        return (e, m, fake)
    }

    /// The runner a model starts with, no fake installed, is the one that hands over exactly the invocation's variables:
    /// Brainmerge's own environment (an API key, another account's CLAUDE_CONFIG_DIR) never reaches Claude Code. A
    /// system program stands in for Claude Code.
    /// Wide bounds: the main actor is shared by the whole suite, so this test can wait its turn for a long time.
    @Test(.timeLimit(.minutes(5))) func theModelsOwnRunnerPassesOnlyTheseVariables() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let runner = model(e).limitsRunner
        let invocation = ClaudeCodeLimits.Invocation(executable: "/usr/bin/env", arguments: [], directory: e.home.url,
                                                     environment: ["HOME": e.home.url.path, "PATH": ClaudeCodeLimits.path], timeout: 10)
        // Off the main actor, like the app runs it.
        let result = try await Task.detached { try runner(invocation) }.value
        #expect(result.status == 0)
        // Only names in a failure's message (a Bool, so the values are not printed): a value handed over by mistake
        // could be a key.
        let lines = Set(result.stdout.split(separator: "\n").map(String.init))
        let exact = lines == ["HOME=\(e.home.url.path)", "PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        #expect(exact, "\(lines.map { $0.prefix { $0 != "=" } }.sorted())")
    }

    @Test func aClickAsksThatAccountsClaudeCode() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("client")
        let environment = ["HOME": e.home.url.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                           "CLAUDE_CONFIG_DIR": e.home.url.appending(path: ".claude-client").path]
        #expect(fake.runs == [
            ClaudeCodeLimits.Invocation(executable: "/fake/claude", arguments: ["--version"], directory: e.home.paths.home, environment: environment, timeout: 20),
            ClaudeCodeLimits.Invocation(executable: "/fake/claude", arguments: ["-p", "/usage"], directory: e.home.paths.home, environment: environment, timeout: 20),
        ])
        guard case .checked(let lines, let at) = m.limits["client"] else { Issue.record("\(String(describing: m.limits["client"]))"); return }
        #expect(lines == Self.lines)
        #expect(abs(at.timeIntervalSinceNow) < 60)
        #expect(m.limits["ruben"] == nil, "one click asks one account")
    }

    @Test func theFirstAccountRunsOnItsDefaultFolder() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("ruben")
        #expect(fake.runs.map(\.environment) == Array(repeating: ["HOME": e.home.url.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], count: 2))
    }

    /// Brainmerge's own environment can hold an API key, a token or another account's folder: none of it reaches Claude Code.
    @Test func nothingOfBrainmergesEnvironmentReachesClaudeCode() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        m.environment = ["ANTHROPIC_API_KEY": "sentinel-api-key", "CLAUDE_CODE_OAUTH_TOKEN": "sentinel-oauth-token",
                         "CLAUDE_CONFIG_DIR": "/sentinel/elsewhere", "PATH": "/sentinel/bin"]
        await m.checkLimits("client")
        #expect(fake.runs.count == 2)
        for run in fake.runs {
            #expect(Set(run.environment.keys) == ["HOME", "PATH", "CLAUDE_CONFIG_DIR"])
            #expect(!run.environment.values.contains { $0.contains("sentinel") }, "\(run.environment)")
        }
    }

    /// Kept in memory only: no file Brainmerge writes holds a percentage or a reset time.
    @Test func theLimitsAreNeverWritten() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("client")
        await m.refreshUsage()
        _ = await m.waitForWork(limit: .seconds(5))
        #expect(m.limits["client"] != nil)
        let found = Self.files(in: e.home.url) { $0.contains("Test/Zone") || $0.contains("42% used") }
        #expect(found.isEmpty, "\(found)")
    }

    nonisolated static func files(in folder: URL, where holds: (String) -> Bool) -> [String] {
        var found: [String] = []
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walk?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, let data = try? Data(contentsOf: url) else { continue }
            if holds(String(decoding: data, as: UTF8.self)) { found.append(url.lastPathComponent) }
        }
        return found
    }

    @Test func anAccountWithoutClaudeCodeHasNothingToCheck() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        var request = IdentityManager.AddRequest(name: "Desk"); request.surfaces = Surfaces(desktop: true, cli: false)
        _ = try e.manager.add(request)
        m.reload()
        #expect(!m.canCheckLimits("desk"))
        await m.checkLimits("desk")
        #expect(fake.runs.isEmpty && fake.binaryLookups == 0)
        #expect(m.limits["desk"] == nil)
    }

    @Test func aClaudeCodeOnlyAccountCanCheck() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        var request = IdentityManager.AddRequest(name: "Terminal"); request.surfaces = Surfaces(desktop: false, cli: true)
        _ = try e.manager.add(request)
        m.reload()
        #expect(m.canCheckLimits("terminal") && m.canCheckLimits("client") && m.canCheckLimits("ruben"))
        await m.checkLimits("terminal")
        #expect(fake.runs.first?.environment["CLAUDE_CONFIG_DIR"] == e.home.url.appending(path: ".claude-terminal").path)
        if case .checked = m.limits["terminal"] {} else { Issue.record("\(String(describing: m.limits["terminal"]))") }
    }

    /// A capture or a demo never asks the owner's real Claude Code.
    @Test func aDemoNeverAsks() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        m.environment = ["BRAINMERGE_HOME": e.home.url.path]
        await m.checkLimits("client")
        #expect(fake.runs.isEmpty && fake.binaryLookups == 0)
        #expect(m.limits["client"] == .refused("Brainmerge does not check limits in a demo."))
    }

    @Test func aRefusalShowsItsSentenceAndNothingElse() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        FakeClaudeCode(version: "2.1.200 (Claude Code)\n").install(in: m)
        await m.checkLimits("client")
        #expect(m.limits["client"] == .refused("Update Claude Code to check limits from here."))
        let unsigned = FakeClaudeCode()
        unsigned.install(in: m, binary: .notSigned(e.home.url.appending(path: ".local/bin/claude").path))
        await m.checkLimits("client")
        #expect(m.limits["client"] == .refused("The Claude Code at ~/.local/bin/claude is not signed by Anthropic, so Brainmerge will not run it."))
        #expect(unsigned.runs.isEmpty)
    }

    /// Bounded: a second click that asks again fails with four starts instead of waiting forever on the held answer.
    /// Five minutes, not one: the whole suite shares the main actor, so a step can wait its turn for a minute.
    @Test(.timeLimit(.minutes(5))) func aSecondClickWhileCheckingAsksOnce() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        let gate = Gate()
        let fake = FakeClaudeCode(gate: gate)
        fake.install(in: m)
        let first = Task { await m.checkLimits("client") }
        for _ in 0..<1000 where m.limits["client"] != .checking { await Task.yield() }
        #expect(m.limits["client"] == .checking)
        var secondReturned = false
        let second = Task { await m.checkLimits("client"); secondReturned = true }
        // The second click is decided while the first still waits: it returns, or (the bug) starts Claude Code again.
        for _ in 0..<500 where !secondReturned && fake.runs.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        gate.open()
        await first.value
        await second.value
        #expect(fake.runs.count == 2, "\(fake.runs.map(\.arguments))")
        if case .checked = m.limits["client"] {} else { Issue.record("\(String(describing: m.limits["client"]))") }
    }

    /// Limits belong to one login. An account removed, added again under the same name, or moved to another Claude Code
    /// folder is another person: its card starts empty. The other accounts keep theirs.
    @Test(arguments: ["removed", "added again", "another folder"])
    func anotherLoginUnderTheSameCardStartsEmpty(_ change: String) async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("client")
        await m.checkLimits("ruben")
        var state = try e.store.load()
        let index = try #require(state.identities.firstIndex { $0.slug == "client" })
        switch change {
        case "removed": state.identities.remove(at: index)
        case "added again": state.identities[index] = Identity(slug: "client", name: "Client", tint: state.identities[index].tint)
        default: state.identities[index].cliProfilePath = e.home.url.appending(path: ".claude-elsewhere").path
        }
        try e.store.save(state)
        m.reload()
        #expect(m.limits["client"] == nil, "\(change)")
        if case .checked = m.limits["ruben"] {} else { Issue.record("\(change): \(String(describing: m.limits["ruben"]))") }
    }

    /// Logged out of Claude Code and in again as another person, in the same folder: the card starts empty. Only two
    /// known logins that differ drop it: a logout alone, a file not read yet, or the same person again keep what was found.
    @Test func anotherLoginInTheSameFolderStartsEmpty() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        let client = CLIProfile(directory: try #require(try e.store.load().identity(slug: "client")).cliProfile(in: e.home.paths))
        func record(_ email: String) throws {
            let json = #"{"oauthAccount":{"emailAddress":"\#(email)","displayName":"Someone"}}"#
            try Data(json.utf8).write(to: client.accountFile)
        }
        func kept(_ step: String) {
            if case .checked = m.limits["client"] {} else { Issue.record("\(step): \(String(describing: m.limits["client"]))") }
        }
        try record("a@example.com")
        m.refreshCodeAccounts()
        await m.checkLimits("client")
        kept("checked")
        try FileManager.default.removeItem(at: client.accountFile)
        m.refreshCodeAccounts()
        kept("logged out")
        try record("A@example.com")
        m.refreshCodeAccounts()
        kept("the same person")
        try record("b@example.com")
        m.refreshCodeAccounts()
        #expect(m.limits["client"] == nil)
    }

    /// Checked before Claude Code's login was known: nothing to tell another person from, so it stays.
    @Test func limitsCheckedBeforeTheLoginWasKnownStay() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("client")
        let client = CLIProfile(directory: try #require(try e.store.load().identity(slug: "client")).cliProfile(in: e.home.paths))
        try Data(#"{"oauthAccount":{"emailAddress":"b@example.com"}}"#.utf8).write(to: client.accountFile)
        m.refreshCodeAccounts()
        if case .checked = m.limits["client"] {} else { Issue.record("\(String(describing: m.limits["client"]))") }
    }

    /// A new name or color is the same person: what was found stays.
    @Test func aRenameKeepsTheLimits() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.checkLimits("client")
        var state = try e.store.load()
        let index = try #require(state.identities.firstIndex { $0.slug == "client" })
        state.identities[index].name = "Studio"
        state.identities[index].tint = .green
        try e.store.save(state)
        m.reload()
        if case .checked = m.limits["client"] {} else { Issue.record("\(String(describing: m.limits["client"]))") }
    }

    /// An answer that comes back after its account was replaced is not shown on the new one's card.
    @Test(.timeLimit(.minutes(5))) func anAnswerForAReplacedAccountIsDropped() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        let gate = Gate()
        let fake = FakeClaudeCode(gate: gate)
        fake.install(in: m)
        let click = Task { await m.checkLimits("client") }
        for _ in 0..<1000 where m.limits["client"] != .checking { await Task.yield() }
        #expect(m.limits["client"] == .checking)
        var state = try e.store.load()
        let index = try #require(state.identities.firstIndex { $0.slug == "client" })
        state.identities[index] = Identity(slug: "client", name: "Client", tint: state.identities[index].tint)
        try e.store.save(state)
        m.reload()
        gate.open()
        await click.value
        #expect(m.limits["client"] == nil, "\(String(describing: m.limits["client"]))")
    }

    /// Never on a timer: the clocks' work and the screen's own refreshes never ask.
    @Test func onlyAClickAsks() async throws {
        let (e, m, fake) = try setUp(); defer { e.home.remove() }
        m.diskMeasure = { _, _ in nil }
        m.reload()
        m.refreshMemory()
        m.refreshCodeAccounts()
        await m.onProjectsTick()?.value
        await m.refreshUsage()
        await m.refreshDisk(force: true)
        await m.checkClaudeUpdate()
        m.windowBecameActive()
        #expect(fake.runs.isEmpty && fake.binaryLookups == 0)
        #expect(m.limits.isEmpty)
    }

    /// The one place in the app that asks is the button's action.
    @Test func theOnlyCallerIsTheButton() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI")
        let walk = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var callers: [String: String] = [:]
        for case let url as URL in walk.allObjects where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("checkLimits(") || text.contains("ClaudeCodeLimits.check(") { callers[url.lastPathComponent] = text }
        }
        #expect(Set(callers.keys) == ["AppModel.swift", "UsageView.swift"], "\(callers.keys.sorted())")
        let view = try #require(callers["UsageView.swift"])
        #expect(view.matches(of: #/checkLimits\(/#).count == 1)
        #expect(view.contains(#/Button\("Check limits"\)\s*\{[^}]*checkLimits\(/#), "the call is the button's action")
        #expect(!view.contains("ClaudeCodeLimits.check("))
    }

    // MARK: Texts

    @Test func aLimitReadsAsClaudeCodeSaysIt() {
        let line = LimitLine(label: "Current week (all models)", percent: 42, resets: "Oct 2, 9am (Europe/Zurich)")
        #expect(LimitsText.percent(line) == "42%")
        #expect(LimitsText.percent(LimitLine(label: "Current session", percent: 12.5, resets: nil)) == "12.5%")
        #expect(LimitsText.resets(line) == "Resets Oct 2, 9am (Europe/Zurich)")
        #expect(LimitsText.resets(LimitLine(label: "Current session", percent: 0, resets: nil)) == nil)
        #expect(LimitsText.accessibilityLabel(line) == "Current week (all models): 42% used, resets Oct 2, 9am (Europe/Zurich)")
        #expect(LimitsText.accessibilityLabel(LimitLine(label: "Current session", percent: 3, resets: nil)) == "Current session: 3% used")
    }

    @Test func checkedAtIsHoursAndMinutes() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-25T21:05:00Z"))
        #expect(LimitsText.checkedAt(date, timeZone: try #require(TimeZone(identifier: "UTC"))) == "Checked at 21:05")
        #expect(LimitsText.checkedAt(date, timeZone: try #require(TimeZone(identifier: "Europe/Zurich"))) == "Checked at 23:05")
        #expect(LimitsText.checkedAt(date.addingTimeInterval(-12 * 3600), timeZone: try #require(TimeZone(identifier: "UTC"))) == "Checked at 09:05")
    }

    /// VoiceOver tells apart the two buttons of a shared card, and the tooltip promises no count of starts (a click
    /// starts Claude Code twice: its version, then /usage).
    @Test func eachButtonNamesItsAccount() throws {
        #expect(LimitsText.buttonLabel(name: "Client") == "Check limits for Client")
        #expect(LimitsText.buttonHelp == "Asks this account's Claude Code, like typing /usage")
        let view = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/BrainmergeUI/Screens/UsageView.swift"), encoding: .utf8)
        #expect(view.contains(#/Button\("Check limits"\)[^\n]*\n(\s*\.[^\n]*\n)*?\s*\.accessibilityLabel\(LimitsText\.buttonLabel\(name: name\)\)/#))
        #expect(view.contains(".help(LimitsText.buttonHelp)"))
    }

    @Test func aSharedCardNamesWhoseLimitsTheyAre() {
        #expect(LimitsText.title(name: "Client", shared: false) == "Limits")
        #expect(LimitsText.title(name: "Client", shared: true) == "Limits for Client")
    }
}
