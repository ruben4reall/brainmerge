import ArgumentParser
import Foundation
import BrainmergeCore

/// Called by each account's SessionStart hook: links the memory of the project the session starts in, so a project
/// opened while Brainmerge is closed already writes its first note into the memory. With --hook it prints nothing (what a
/// SessionStart hook prints goes into the session) and always exits 0; it logs to sync.log instead.
struct WireCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "wire",
                                                    abstract: "Link one project's memory for an account: the current folder, or with --hook the folder a session starts in (used by the SessionStart hook; prints nothing, always exits 0).")
    @Option var identity: String
    @Flag(help: "Read the session Claude Code sends on the standard input, print nothing and always exit 0.") var hook = false

    func run() throws {
        let context = Context()
        guard hook else {
            let result = try wire(FileManager.default.currentDirectoryPath, context: context, lockTimeout: 20)
            print(Self.describe(result) ?? "Already linked.")
            return
        }
        let log = SyncLog(paths: context.paths)
        guard let input = SessionStartInput.decode(FileHandle.standardInput.readDataToEndOfFile()) else {
            log.write("\(identity): session start without a folder, nothing linked")
            return
        }
        // Bounded well under the hook's 5 seconds: a save in progress holds the lock, and the next session start links it.
        let timeout = Double(ProcessInfo.processInfo.environment["BRAINMERGE_LOCK_TIMEOUT"] ?? "") ?? 2
        do {
            if let line = Self.describe(try wire(input.cwd, context: context, lockTimeout: timeout)) { log.write("\(identity): \(line)") }
        } catch BrainmergeError.lockTimeout {
            log.write("\(identity): memory lock held by another process, link skipped")
        } catch {
            log.write("\(identity): \(error)")
        }
    }

    func wire(_ path: String, context: Context, lockTimeout: TimeInterval) throws -> MemoryWiring.Result {
        let state = try context.store.load()
        guard let account = state.identity(slug: identity) else { throw BrainmergeError.identityNotFound(identity) }
        guard let folder = state.brain(for: account) else { throw BrainmergeError.brainNotConfigured }
        let brain = Brain(root: folder.url)
        guard brain.isInitialized else { throw BrainmergeError.brainNotFound(brain.root.path) }
        let profile = CLIProfile(directory: account.cliProfile(in: context.paths))
        guard profile.exists else { throw BrainmergeError.profileMissing(profile.directory.path) }
        let wiring = MemoryWiring(brain: brain, paths: context.paths, machineID: state.machineID, knownRoots: state.brains.map(\.url))
        return try BrainGit(brain: brain).withLock(timeout: lockTimeout) {
            try wiring.wireOne(projectPath: path, profile: profile, identitySlug: account.slug)
        }
    }

    /// One line when something changed, nil when the project was already linked.
    static func describe(_ result: MemoryWiring.Result) -> String? {
        var parts: [String] = []
        if !result.linked.isEmpty { parts.append("linked \(result.linked.joined(separator: ", "))") }
        if !result.adopted.isEmpty { parts.append("moved its notes into the memory") }
        if !result.conflicts.isEmpty { parts.append("kept \(result.conflicts.joined(separator: ", ")) beside the memory's own") }
        if !result.external.isEmpty { parts.append("left as is: \(result.external.joined(separator: ", "))") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}
