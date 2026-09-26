import ArgumentParser
import Foundation
import BrainmergeCore

/// Called by each identity's Stop hook: commits exactly what this account wrote (its list, see TouchedLedger), in each
/// memory it wrote to, under its name. Always exits with 0: never block Claude.
struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Commit what an identity wrote in the memory, under its name. Used by the Stop hook; always exits 0.")
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
            let own = Brain(root: folder.url)
            guard own.isInitialized else { log.write("\(identity): memory missing at \(own.root.path)"); return }
            // Its own memory, and any other one it wrote a note in (or left a list in, when a save stopped half way).
            let others = state.brains.filter { $0.id != folder.id }.filter { other in
                let ledger = TouchedLedger(brain: Brain(root: other.url), slug: id.slug)
                return Brain(root: other.url).isInitialized && [ledger.file, ledger.sending].contains { FileManager.default.fileExists(atPath: $0.path) }
            }
            var saved = 0
            var held: Set<String> = []
            var behind = 0
            var wentThrough = 0
            // Each memory on its own: one that waits (a lock, the person's merge left open for days) never stops the
            // others. A memory that failed keeps its list for the next save (see AccountSave).
            for memory in [folder] + others {
                let brain = Brain(root: memory.url)
                try? brain.ensureIgnores()
                let git = BrainGit(brain: brain)
                let store = HeldStore(paths: context.paths, memoryID: memory.id)
                do {
                    let outcome = try git.withLock(timeout: timeout) { try AccountSave(brain: brain, git: git, held: store).run(for: id) }
                    saved += outcome.saved.count
                    held.formUnion(outcome.held.map { "\(memory.id)/\($0.path)" })
                    wentThrough += 1
                } catch BrainmergeError.lockTimeout {
                    log.write("\(identity): \(memory.name): brain lock held by another process, skipped")
                } catch {
                    log.write("\(identity): \(memory.name): \(error)")
                }
                behind += git.indexBehind.count
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if wentThrough > 0 {
                log.write("\(identity): \(saved == 0 ? "nothing to commit" : "committed \(saved) file\(saved == 1 ? "" : "s")") in \(ms) ms")
            }
            // The save is made; only git's own list of what is staged waits (see BrainGit.followCommit).
            if behind > 0 {
                log.write("\(identity): another git held the memory's index, it catches up with \(behind) file\(behind == 1 ? "" : "s") at the next save")
            }
            // Never the line, never the value: how many files, and why.
            if !held.isEmpty {
                log.write("\(identity): held back \(held.count) file\(held.count == 1 ? " (looks like a key)" : "s (they look like keys)")")
            }
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
