import ArgumentParser
import Foundation
import BrainmergeCore

/// Called by each account's PostToolUse hook after an edit tool wrote a file: when the file is a note of one of the
/// memories, its path goes on this account's list, and the account's next save commits exactly that. It prints nothing (a
/// hook's output reaches the session), always exits 0, starts nothing and stays well under the hook's time.
struct TouchedCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "touched",
                                                    abstract: "Note a file an account wrote in a memory. Used by the PostToolUse hook; prints nothing, always exits 0.")
    @Option var identity: String

    func run() {
        guard let input = TouchedInput.decode(FileHandle.standardInput.readDataToEndOfFile()) else { return }
        let context = Context()
        // The account must be known: its slug names the list's file, and nothing else may.
        guard let state = try? context.store.load(), state.identity(slug: identity) != nil else { return }
        let brains = state.brains.map { Brain(root: $0.url) }.filter(\.isInitialized)
        guard let found = TouchedLedger.locate(input.filePath, in: brains) else { return }
        do {
            try TouchedLedger(brain: found.brain, slug: identity).append(found.path)
        } catch {
            SyncLog(paths: context.paths).write("\(identity): could not note \(found.path): \(error)")
        }
    }
}
