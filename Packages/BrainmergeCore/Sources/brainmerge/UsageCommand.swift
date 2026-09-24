import ArgumentParser
import Foundation
import BrainmergeCore

/// What an account spent, from Claude Code's local transcripts: the same numbers as the Usage screen.
struct UsageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "usage", abstract: "Output and context tokens per account, today, 7 days and 30 days, from the local transcripts.")
    @Option(help: "One identity (its slug). Default: every identity.") var identity: String?
    @Option(help: "A Claude Code folder to read directly, instead of the identities.") var profile: String?
    @Option(help: "Where the incremental cache lives (default: Brainmerge's Application Support folder).") var cache: String?
    @Flag(help: "Print the elapsed time and the memory used by the read.") var timing = false
    @Flag var json = false

    func run() throws {
        let context = Context()
        let now = Date(), since = now.addingTimeInterval(-30 * 86_400)
        var targets: [(label: String, profile: CLIProfile, cache: URL)] = []
        if let profile {
            let dir = URL(fileURLWithPath: profile, isDirectory: true)
            targets.append(("profile", CLIProfile(directory: dir), cache.map { URL(fileURLWithPath: $0) } ?? context.paths.appSupport.appending(path: "usage/profile-\(ProjectSlug.slug(forPath: dir.path)).json")))
        } else {
            let state = try context.store.load()
            for id in state.identities where identity == nil || id.slug == identity {
                targets.append((id.name, CLIProfile(directory: id.cliProfile(in: context.paths)), cache.map { URL(fileURLWithPath: $0) } ?? context.paths.appSupport.appending(path: "usage/\(id.slug).json")))
            }
            if let identity, targets.isEmpty { throw BrainmergeError.identityNotFound(identity) }
        }
        let start = Date()
        var report: [[String: Any]] = []
        for target in targets {
            let samples = try UsageReader(cacheFile: target.cache).read(profile: target.profile, since: since, now: now)
            let summary = UsageSummary.make(samples, now: now)
            report.append(["account": target.label, "today": summary.todayOutput, "todayContext": summary.today,
                           "week": summary.weekOutput, "weekContext": summary.week, "month": summary.monthOutput, "monthContext": summary.month,
                           "projects": summary.byProject.map { ["name": $0.key, "output": $0.output] },
                           "models": summary.byModel.map { ["name": $0.key, "output": $0.output] }])
        }
        let elapsed = Date().timeIntervalSince(start)
        if json {
            print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } else {
            for entry in report {
                print("\(entry["account"]!): today \(entry["today"]!) written, 7 days \(entry["week"]!), 30 days \(entry["month"]!) (context \(entry["monthContext"]!))")
                for project in entry["projects"] as? [[String: Any]] ?? [] { print("  \(project["name"]!)  \(project["output"]!)") }
            }
        }
        if timing {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
            let resident = result == KERN_SUCCESS ? Int64(info.resident_size) : 0
            let peak = Int64(usage.ru_maxrss)
            FileHandle.standardError.write(Data(String(format: "timing: %.2f s, peak %d MB, resident now %d MB\n", elapsed, peak / 1_048_576, resident / 1_048_576).utf8))
        }
    }
}
