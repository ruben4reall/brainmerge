import ArgumentParser
import Foundation
import BrainmergeCore

/// Called by each identity's Stop hook. Always exits with 0: never block Claude.
struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Commit the brain under an identity's name. Used by the Stop hook; always exits 0.")
    @Option var identity: String

    func run() {
        let context = Context()
        let log = SyncLog(paths: context.paths)
        let start = Date()
        let timeout = Double(ProcessInfo.processInfo.environment["BRAINMERGE_LOCK_TIMEOUT"] ?? "") ?? 20
        do {
            let state = try context.store.load()
            guard let id = state.identity(slug: identity) else { log.write("\(identity): unknown identity"); return }
            guard let folder = state.brain(for: id) else { log.write("\(identity): no memory configured"); return }
            let brain = Brain(root: folder.url)
            guard brain.isInitialized else { log.write("\(identity): memory missing at \(brain.root.path)"); return }
            let git = BrainGit(brain: brain)
            let committed = try git.withLock(timeout: timeout) {
                try git.commitAll(authorName: id.name, authorEmail: id.gitAuthorEmail, message: "Brain update by \(id.name)")
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            log.write("\(identity): \(committed ? "committed" : "nothing to commit") in \(ms) ms")
        } catch BrainmergeError.lockTimeout {
            log.write("\(identity): brain lock held by another process, skipped")
        } catch {
            log.write("\(identity): \(error)")
        }
    }
}

struct SyncLog {
    let file: URL
    init(paths: Paths) { file = paths.logsDir.appending(path: "sync.log") }

    func write(_ line: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
