import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct UsageModelTests {
    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    func assistant(id: String, at date: Date, output: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(date.formatted(Self.iso))\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-fable-5-1\",\"usage\":{\"input_tokens\":1,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":10,\"output_tokens\":\(output)}}}\n"
    }

    @Test func accountsSharingTheirHistoryAreCountedOnce() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.sharedHistory = true
        let client = try e.manager.add(request)
        // Shared history: Client's projects folder is a link to the primary account's.
        let clientProjects = CLIProfile(directory: client.cliProfile(in: e.home.paths)).projectsDir
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: clientProjects.path)) != nil)
        let project = e.primaryProfile.projectsDir.appending(path: "-Users-me-atelier", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data((assistant(id: "a", at: Date(), output: 120) + assistant(id: "b", at: Date(), output: 30)).utf8).write(to: project.appending(path: "s.jsonl"))
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false)
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.reload()
        await model.refreshUsage()
        #expect(model.usage.count == 1)
        #expect(model.usage.first?.slugs == ["ruben", "client"])
        #expect(model.usage.first?.shared == true)
        #expect(model.usage.first?.summary.todayOutput == 150)
        #expect(model.usage.first?.summary.byProject.first?.key == "-Users-me-atelier")
        #expect(model.usageUpdatedAt != nil)
    }

    /// The card before the first figures: the screen's first frame comes before its read starts, and must never say
    /// "Nothing yet" over transcripts that hold data. Nothing yet only once a read has finished and found nothing.
    @Test func theFirstVisitSaysReadingNeverNothingYet() {
        let never = UsageView.Placeholder.of(refreshing: false, updated: nil)
        #expect(never == .reading && never.spinner && never.text == "Reading the transcripts…")
        #expect(UsageView.Placeholder.of(refreshing: true, updated: nil) == .reading)
        #expect(UsageView.Placeholder.of(refreshing: true, updated: Date()) == .reading)
        let empty = UsageView.Placeholder.of(refreshing: false, updated: Date())
        #expect(empty == .nothingYet && !empty.spinner)
        #expect(empty.text == "Nothing yet. Open an account and work in Claude Code: what it spends shows up here.")
    }

    @Test func tokensReadLikeNumbers() {
        #expect(TokenFormat.short(0) == "0")
        #expect(TokenFormat.short(999) == "999")
        #expect(TokenFormat.short(12_400) == "12.4k")
        #expect(TokenFormat.short(1_250_000) == "1.3M")
        #expect(TokenFormat.short(999_950) == "1M")
    }
}
