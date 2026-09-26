import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// Settings opens on Health (the doctor's findings, each with its one button), a failed save shows on the account's card
/// and the Memory screen, and a macOS or Claude update runs the check once on its own.
@MainActor @Suite struct HealthTests {
    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        model.environment = [:]
        return model
    }

    /// Counts the doctor's runs and hands back what the test decides.
    final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var findings: [Doctor.Finding] = []
        var runs: Int { lock.withLock { count } }
        func run(_ doctor: Doctor) -> [Doctor.Finding] { lock.withLock { count += 1 }; return findings }
    }

    final class Version: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    static let problems = [
        Doctor.Finding(level: .warning, title: "Command line", detail: "missing", plain: "The command line is not installed.", fix: .installCLI),
        Doctor.Finding(level: .error, title: "Client: launcher", detail: "missing", plain: "The app of Client is missing.", fix: .rebuild(slug: "client")),
        Doctor.Finding(level: .ok, title: "git", detail: "ok", plain: "Apple's Command Line Tools are installed."),
    ]

    // MARK: After an update

    /// The first look only notes the versions; a macOS or Claude version the setup was not checked after runs the check
    /// exactly once, however many times the app looks, and says one line.
    @Test func aVersionChangeRunsTheCheckExactlyOnce() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        let runs = Runs()
        m.runHealth = { runs.run($0) }
        let macOS = Version("26.0.0")
        m.macOSVersion = { macOS.value }
        m.reload()

        await m.checkClaudeUpdate()
        #expect(runs.runs == 0 && m.healthNote == nil)
        #expect(try e.store.load().lastCheckedMacOS == "26.0.0")
        #expect(try e.store.load().lastCheckedClaude == "2.7032.0")
        await m.checkClaudeUpdate()
        #expect(runs.runs == 0)

        macOS.value = "26.1.0"
        async let first: Void = m.checkClaudeUpdate()
        async let second: Void = m.checkClaudeUpdate()
        _ = await (first, second)
        #expect(runs.runs == 1)
        #expect(m.healthNote == "Checked after the macOS update: all good.")
        await m.checkClaudeUpdate()
        m.windowBecameActive()
        await m.checkClaudeUpdate()
        #expect(runs.runs == 1)
        #expect(try e.store.load().lastCheckedMacOS == "26.1.0")

        // Claude was updated since the last check: once more, and the line counts what is left to fix.
        try e.store.update { $0.lastCheckedClaude = "2.6000.0" }
        runs.findings = Self.problems
        await m.checkClaudeUpdate()
        await m.checkClaudeUpdate()
        #expect(runs.runs == 2)
        #expect(m.healthNote == "Checked after the Claude update: 2 things to fix.")
        #expect(m.healthProblems.map(\.title) == ["Command line", "Client: launcher"])
        m.dismissHealthNote()
        #expect(m.healthNote == nil)
    }

    /// A capture or a demo never runs the doctor on its demo home: Health says everything is in place.
    @Test func aCaptureNeverRunsTheCheck() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        let runs = Runs()
        runs.findings = Self.problems
        m.runHealth = { runs.run($0) }
        m.environment = ["BRAINMERGE_CAPTURE": "1"]
        m.reload()
        _ = await m.checkHealth()
        try e.store.update { $0.lastCheckedClaude = "2.6000.0" }
        await m.checkClaudeUpdate()
        #expect(runs.runs == 0)
        #expect(m.health == [] && m.healthProblems.isEmpty && m.healthNote == nil)
    }

    // MARK: Settings > Health

    /// The doctor runs off the main thread within its budget: one that takes longer is left, and Health says so.
    @Test func theCheckGivesUpAfterItsBudget() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        m.healthBudget = .milliseconds(200)
        // Far past the budget: waiting for it would give its empty list, not nil. (No wall-clock bound here: other suites
        // keep the main actor busy, and the answer alone shows the check did not wait.)
        m.runHealth = { _ in Thread.sleep(forTimeInterval: 5); return [] }
        #expect(await m.checkHealth() == nil)
        #expect(m.healthTimedOut && m.health == nil && !m.healthChecking)

        m.healthBudget = .seconds(10)
        m.runHealth = { $0.run() }
        let found = try #require(await m.checkHealth())
        #expect(!m.healthTimedOut)
        // The real doctor on this home: no command line link yet, so every hook would call nothing.
        #expect(found.contains { $0.title == "Command line" && $0.fix == .installCLI })
        #expect(m.healthProblems.allSatisfy { $0.level != .ok })
        #expect(m.healthProblems.contains { $0.title == "Command line" })
    }

    /// A button mends its finding, then the check runs again and the row is gone.
    @Test func aFixMendsItsFindingAndChecksAgain() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        let cli = e.home.url.appending(path: "Applications/Brainmerge.app/Contents/MacOS/brainmerge-cli")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        m.commandLine = { cli }
        m.reload()
        try HookInstaller.remove(settingsFile: e.primaryProfile.settingsFile)
        _ = await m.checkHealth()
        #expect(m.healthProblems.first { $0.title == "Perso: hooks" }?.fix == .repairHooks)

        await m.applyFix(.repairHooks)
        #expect(!m.healthProblems.contains { $0.title == "Perso: hooks" })
        #expect(HookInstaller.health(settingsFile: e.primaryProfile.settingsFile, cliPath: e.cliPath, slug: "perso") == .current)

        // A memory whose folder is gone: the folder where it lives now.
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let moved = e.home.url.appending(path: "Moved/Work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: work.url, to: moved)
        m.reload()
        _ = await m.checkHealth()
        #expect(m.healthProblems.first { $0.title == "Memory: Work" }?.fix == .chooseMemory(brainID: "work"))
        await m.chooseMemoryFolder("work", at: moved)
        #expect(!m.healthProblems.contains { $0.title == "Memory: Work" })
        #expect(m.brains.first { $0.id == "work" }?.path == moved.path)
        #expect(m.message == nil)
    }

    /// Settings opens on Health: it is the first of its sections.
    @Test func settingsOpensOnHealth() throws {
        let settings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens/SettingsView.swift")
        let source = try String(contentsOf: settings, encoding: .utf8)
        let first = try #require(source.range(of: "section(\""))
        #expect(source[first.lowerBound...].hasPrefix("section(\"Health\")"))
    }

    @Test func eachFixHasItsButton() {
        #expect(HealthText.button(.repairLinks(brainID: "shared")) == "Repair links")
        #expect(HealthText.button(.rebuild(slug: "work")) == "Rebuild")
        #expect(HealthText.button(.installCLI) == "Install command line")
        #expect(HealthText.button(.chooseMemory(brainID: "work")) == "Choose memory folder")
        #expect(HealthText.button(.repairHooks) == "Repair hooks")
        #expect(HealthText.button(.installAppleTools) == "Install Apple's tools")
    }

    // MARK: Failed saves

    /// The mark shows only while the account's latest save failed and it has not saved since.
    @Test func theFailureMarkShowsOnlyWhenTheLatestSaveFailedAfterTheLastSuccess() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let perso = try e.manager.adoptPrimary(name: "Perso")
        let m = model(e)
        m.reload()
        let statuses = SaveStatusStore(paths: e.home.paths)
        let now = Date()
        m.now = { now }

        #expect(m.saveFailure(of: "perso") == nil)
        let failed = SaveStatus(date: now.addingTimeInterval(-3 * 3600), outcome: .failed, reason: .locked)
        statuses.write(failed, slug: "perso")
        m.refreshMemory()
        #expect(m.saveFailure(of: "perso")?.reason == .locked)
        #expect(m.saveFailureSentence(of: "perso") == "Last save failed 3 hours ago: the memory was locked by another program.")

        // It saved since, in its memory: the older failure is over.
        try TouchedLedger(brain: e.brain, slug: "perso").append(".brainmerge/projects.json")
        try AccountSave(brain: e.brain, git: BrainGit(brain: e.brain), held: HeldStore(paths: e.home.paths, memoryID: "shared")).run(for: perso)
        #expect(try BrainGit(brain: e.brain).log(limit: 1).first?.authorName == "Perso")
        m.refreshMemory()
        #expect(m.saveFailure(of: "perso") == nil)

        // A failure after that save shows again.
        statuses.write(SaveStatus(date: Date().addingTimeInterval(120), outcome: .failed, reason: .diskFull), slug: "perso")
        m.refreshMemory()
        #expect(m.saveFailure(of: "perso")?.reason == .diskFull)

        for outcome in [SaveStatus.Outcome.committed, .nothing, .held] {
            statuses.write(SaveStatus(date: Date().addingTimeInterval(180), outcome: outcome, reason: outcome == .held ? .heldBack : nil), slug: "perso")
            m.refreshMemory()
            #expect(m.saveFailure(of: "perso") == nil, "\(outcome)")
        }
    }

    /// When the save failed and why, in words from a closed list: never git's own words, never a path.
    @Test func failureSentencesSayWhenAndWhy() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func status(_ ago: TimeInterval, _ reason: SaveStatus.Reason?) -> SaveStatus {
            SaveStatus(date: now.addingTimeInterval(-ago), outcome: .failed, reason: reason)
        }
        #expect(HealthText.failure(status(3 * 3600, .locked), now: now) == "Last save failed 3 hours ago: the memory was locked by another program.")
        #expect(HealthText.failure(status(20, .diskFull), now: now) == "Last save failed just now: the disk is full.")
        #expect(HealthText.failure(status(-5, .diskFull), now: now) == "Last save failed just now: the disk is full.")
        #expect(HealthText.failure(status(60, .gitMissing), now: now) == "Last save failed 1 minute ago: Apple's Command Line Tools are missing.")
        #expect(HealthText.failure(status(2 * 86_400, .notARepository), now: now)
            == "Last save failed 2 days ago: the memory folder is missing or is not a git repository.")
        #expect(HealthText.failure(status(3600, .unknown), now: now) == "Last save failed 1 hour ago: something unexpected stopped it.")
        #expect(HealthText.failure(status(3600, nil), now: now) == "Last save failed 1 hour ago: something unexpected stopped it.")
        #expect(HealthText.failure(status(3 * 3600, .locked), now: now, account: "Work")
            == "Last save of Work failed 3 hours ago: the memory was locked by another program.")
    }

    @Test func theLineAfterAnUpdateSaysWhatWasChecked() {
        #expect(HealthText.afterUpdate(macOS: false, claude: true, problems: 0) == "Checked after the Claude update: all good.")
        #expect(HealthText.afterUpdate(macOS: false, claude: true, problems: 2) == "Checked after the Claude update: 2 things to fix.")
        #expect(HealthText.afterUpdate(macOS: true, claude: false, problems: 1) == "Checked after the macOS update: 1 thing to fix.")
        #expect(HealthText.afterUpdate(macOS: true, claude: true, problems: 0) == "Checked after the macOS and Claude updates: all good.")
    }
}
