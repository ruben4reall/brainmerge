import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct UsageReaderTests {
    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    func assistant(id: String, model: String = "claude-fable-5-1", at date: Date, input: Int = 2, cacheCreation: Int = 100, cacheRead: Int = 1000, output: Int = 50) -> String {
        let usage = "{\"input_tokens\":\(input),\"cache_creation_input_tokens\":\(cacheCreation),\"cache_read_input_tokens\":\(cacheRead),\"output_tokens\":\(output)}"
        return "{\"type\":\"assistant\",\"uuid\":\"\(UUID().uuidString)\",\"timestamp\":\"\(date.formatted(Self.iso))\",\"message\":{\"id\":\"\(id)\",\"model\":\"\(model)\",\"role\":\"assistant\",\"usage\":\(usage),\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}\n"
    }
    func user(at date: Date) -> String {
        "{\"type\":\"user\",\"uuid\":\"\(UUID().uuidString)\",\"timestamp\":\"\(date.formatted(Self.iso))\",\"message\":{\"role\":\"user\",\"content\":\"hello\"}}\n"
    }

    struct Fixture { let home: TempHome; let profile: CLIProfile; let reader: UsageReader; let project: URL }
    func fixture() throws -> Fixture {
        let home = try TempHome()
        let profile = try CLIProfile.create(at: home.paths.primaryCLIProfile, inheritingFrom: nil)
        let project = profile.projectsDir.appending(path: "-Users-me-atelier", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project.appending(path: "s1/subagents"), withIntermediateDirectories: true)
        return Fixture(home: home, profile: profile, reader: UsageReader(cacheFile: home.paths.appSupport.appending(path: "usage-cache.json")), project: project)
    }

    @Test func parsesAssistantUsageAndDeduplicatesStreamedLines() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        var text = user(at: now)
        text += assistant(id: "msg_1", at: now, output: 5)         // first streaming line: provisional count
        text += assistant(id: "msg_1", at: now, output: 40)        // last line: the real count
        text += assistant(id: "msg_2", model: "claude-opus-5-5", at: now, output: 7)
        try Data(text.utf8).write(to: f.project.appending(path: "s1.jsonl"))
        try Data(assistant(id: "msg_sub", at: now, output: 3).utf8).write(to: f.project.appending(path: "s1/subagents/a.jsonl"))
        let samples = try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now)
        #expect(samples.count == 3)
        #expect(samples.map(\.output).sorted() == [3, 7, 40])
        #expect(samples.allSatisfy { $0.project == "-Users-me-atelier" })
        #expect(Set(samples.map(\.model)) == ["claude-fable-5-1", "claude-opus-5-5"])
        #expect(samples.first { $0.output == 40 }?.total == 2 + 100 + 1000 + 40)
    }

    @Test func incrementalReadOnlyParsesAppendedLines() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        let file = f.project.appending(path: "s2.jsonl")
        try Data(assistant(id: "a", at: now).utf8).write(to: file)
        #expect(try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now).count == 1)
        let cache1 = try UsageReader.Cache.load(f.reader.cacheFile)
        #expect(cache1.files[file.path]?.offset == Int64(try Data(contentsOf: file).count))
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data(assistant(id: "b", at: now).utf8)); try handle.close()
        let again = try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now)
        #expect(again.count == 2)
        let cache2 = try UsageReader.Cache.load(f.reader.cacheFile)
        #expect(cache2.files[file.path]?.parsedLines == 1)   // only the appended line was parsed on the second pass
    }

    @Test func aMessageContinuedOnTheNextPassKeepsItsFinalCount() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        let file = f.project.appending(path: "s3.jsonl")
        try Data(assistant(id: "m", at: now, output: 5).utf8).write(to: file)
        #expect(try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now).map(\.output) == [5])
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data(assistant(id: "m", at: now, output: 40).utf8)); try handle.close()
        let samples = try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now)
        #expect(samples.map(\.output) == [40])
    }

    @Test func bigFilesAreReadInChunksWithoutBreakingLines() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        var text = ""
        for i in 0..<200 { text += assistant(id: "id_\(i)", at: now, output: 10) }   // ~50 KB, in 1 KB chunks
        try Data(text.utf8).write(to: f.project.appending(path: "big.jsonl"))
        let reader = UsageReader(cacheFile: f.reader.cacheFile, chunkSize: 1024)
        let samples = try reader.read(profile: f.profile, since: now.addingTimeInterval(-86_400), now: now)
        #expect(samples.reduce(0) { $0 + $1.output } == 2000)
    }

    @Test func cacheIsAggregatedPrunedAndNotRewrittenWhenNothingChanged() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        var text = ""
        for i in 0..<50 { text += assistant(id: "t_\(i)", at: now, output: 10) }                             // today
        for i in 0..<50 { text += assistant(id: "o_\(i)", at: now.addingTimeInterval(-40 * 86_400), output: 10) }   // too old
        try Data(text.utf8).write(to: f.project.appending(path: "s4.jsonl"))
        let since = now.addingTimeInterval(-30 * 86_400)
        let first = try f.reader.read(profile: f.profile, since: since, now: now)
        #expect(first.reduce(0) { $0 + $1.output } == 500)
        let cache = try UsageReader.Cache.load(f.reader.cacheFile)
        let state = try #require(cache.files.values.first)
        #expect(state.buckets.count <= 2)          // aggregated by day, project and model, not by message
        #expect(state.buckets.allSatisfy { $0.day >= since })   // old samples are pruned
        let mtime = try FileManager.default.attributesOfItem(atPath: f.reader.cacheFile.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 1.1)
        _ = try f.reader.read(profile: f.profile, since: since, now: now)
        let again = try FileManager.default.attributesOfItem(atPath: f.reader.cacheFile.path)[.modificationDate] as? Date
        #expect(mtime == again)                    // nothing changed: the cache isn't rewritten
    }

    @Test func oldFilesAreSkippedWithoutBeingRead() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        let old = f.project.appending(path: "old.jsonl")
        try Data(assistant(id: "old", at: now.addingTimeInterval(-60 * 86_400)).utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60 * 86_400)], ofItemAtPath: old.path)
        let samples = try f.reader.read(profile: f.profile, since: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(samples.isEmpty)
        #expect(try UsageReader.Cache.load(f.reader.cacheFile).files[old.path] == nil)
    }

    @Test func summaryBucketsByPeriodProjectAndModel() {
        let now = Date()
        func s(_ daysAgo: Double, _ project: String, _ model: String, output: Int) -> UsageSample {
            UsageSample(date: now.addingTimeInterval(-daysAgo * 86_400), project: project, model: model, input: 10, cacheCreation: 0, cacheRead: 100, output: output)
        }
        let samples = [s(0, "atelier", "claude-fable-5-1", output: 500), s(0.5, "atelier", "claude-opus-5-5", output: 100),
                       s(3, "trailbook", "claude-fable-5-1", output: 200), s(12, "trailbook", "claude-fable-5-1", output: 1000), s(40, "x", "y", output: 9999)]
        let summary = UsageSummary.make(samples, now: now)
        #expect(summary.todayOutput == 600 || summary.todayOutput == 500)     // depending on the time: the second sample might be yesterday
        #expect(summary.weekOutput == 800)
        #expect(summary.monthOutput == 1800)
        #expect(summary.byProject.first?.key == "trailbook" && summary.byProject.first?.output == 1200)
        #expect(summary.byModel.first?.key == "claude-fable-5-1" && summary.byModel.first?.output == 1700)
        #expect(summary.byDay.count == 14 && summary.byDay.last?.output == summary.todayOutput)
    }

    @Test func projectNamesComeFromTheTranscriptsCwd() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date(), since = now.addingTimeInterval(-30 * 86_400)
        // The sessions folder is a slug; the lines carry the real folder: the sample is named after it.
        let dir = f.profile.projectsDir.appending(path: "-Volumes-Work-client-site", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let user = #"{"type":"user","cwd":"/Volumes/Work/client-site","timestamp":"2026-09-24T09:00:00.000Z","message":{"role":"user","content":"hi"}}"#
        try Data((user + "\n" + assistant(id: "m1", at: now.addingTimeInterval(-60))).utf8).write(to: dir.appending(path: "s.jsonl"))
        // Without a cwd, the slug stays.
        try Data(assistant(id: "m2", at: now.addingTimeInterval(-60)).utf8).write(to: f.project.appending(path: "s1/s.jsonl"))
        let samples = try f.reader.read(profile: f.profile, since: since, now: now)
        #expect(samples.contains { $0.project == "client-site" })
        #expect(!samples.contains { $0.project == "-Volumes-Work-client-site" })
        #expect(samples.contains { $0.project == "-Users-me-atelier" })
    }

    @Test func fiftyThousandLinesAreReadWithinABoundedMemory() throws {
        let f = try fixture(); defer { f.home.remove() }
        let now = Date()
        let dir = f.profile.projectsDir.appending(path: "-Users-r-big", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Lines like Claude Code's: a long content, then the usage. About 100 MB in all.
        let padding = String(repeating: "x", count: 1800)
        let file = dir.appending(path: "big.jsonl")
        try Data().write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        for i in 0..<50_000 {
            let line = #"{"type":"assistant","cwd":"/Users/r/big","timestamp":"\#(now.formatted(Self.iso))","message":{"id":"msg_\#(i)","model":"claude-fable-5-1","content":[{"type":"text","text":"\#(padding)"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}"#
            handle.write(Data((line + "\n").utf8))
        }
        try handle.close()
        // Measured in a process of its own (the command line), so the other suites running here do not blur the number.
        let cache = f.home.url.appending(path: "usage-cache.json").path
        let result = try Shell().run(Products.brainmerge.path, ["usage", "--profile", f.profile.directory.path, "--cache", cache, "--json", "--timing"],
                                     environment: ["BRAINMERGE_HOME": f.home.url.path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("\"month\" : 200000"))
        let peak = result.stderr.split(separator: "\n").first { $0.hasPrefix("timing:") }
            .flatMap { line -> Int? in
                let parts = line.split(separator: " ")
                guard let index = parts.firstIndex(of: "peak"), index + 1 < parts.count else { return nil }
                return Int(parts[index + 1])
            }
        #expect(peak != nil && peak! < 120, "peak \(peak.map(String.init) ?? "?") MB for a 100 MB transcript")
    }
}
