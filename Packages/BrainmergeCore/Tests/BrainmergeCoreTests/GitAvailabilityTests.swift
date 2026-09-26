import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Records every program a fake shell was asked to run.
final class ShellCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [[String]] = []
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return list }
    func record(_ call: [String]) { lock.lock(); list.append(call); lock.unlock() }
}

@Suite struct GitAvailabilityTests {
    static func shell(status: Int32, path: String, calls: ShellCalls = ShellCalls()) -> Shell {
        Shell { executable, arguments, _, _ in
            calls.record([executable] + arguments)
            return ShellResult(status: status, stdout: path + "\n", stderr: "")
        }
    }

    @Test func noCommandLineToolsMeansUnavailable() {
        let git = GitAvailability(shell: Self.shell(status: 2, path: ""), isExecutable: { _ in true })
        #expect(!git.isAvailable)
    }

    @Test func aToolsFolderWithoutGitMeansUnavailable() {
        let git = GitAvailability(shell: Self.shell(status: 0, path: "/Library/Developer/CommandLineTools"), isExecutable: { _ in false })
        #expect(!git.isAvailable)
    }

    @Test func toolsWithGitMeanAvailableAndTheAnswerIsKeptUntilCheckedAgain() {
        let calls = ShellCalls()
        let seen = ShellCalls()
        let git = GitAvailability(shell: Self.shell(status: 0, path: "/Library/Developer/CommandLineTools", calls: calls),
                                  isExecutable: { path in seen.record([path]); return true })
        #expect(git.isAvailable)
        #expect(git.isAvailable)
        #expect(calls.all == [["/usr/bin/xcode-select", "-p"]])
        #expect(seen.all == [["/Library/Developer/CommandLineTools/usr/bin/git"]])
        git.invalidate()
        _ = git.isAvailable
        #expect(calls.all.count == 2)
    }

    @Test func installAsksAppleOnlyWithAnArgumentList() throws {
        let calls = ShellCalls()
        let git = GitAvailability(shell: Self.shell(status: 0, path: "", calls: calls), isExecutable: { _ in false })
        try git.install()
        #expect(calls.all == [["/usr/bin/xcode-select", "--install"]])
    }

    @Test func brainGitNeverStartsGitWhenItIsMissing() throws {
        let home = try TempHome(); defer { home.remove() }
        let calls = ShellCalls()
        let recording = Shell { executable, arguments, _, _ in
            calls.record([executable] + arguments)
            return ShellResult(status: 0, stdout: "", stderr: "")
        }
        let missing = GitAvailability(shell: Self.shell(status: 2, path: ""), isExecutable: { _ in false })
        let git = BrainGit(brain: Brain(root: home.paths.defaultBrain), shell: recording, availability: missing)
        #expect(throws: BrainmergeError.gitUnavailable) { try git.initIfNeeded() }
        #expect(throws: BrainmergeError.gitUnavailable) { try git.hasChanges() }
        #expect(throws: BrainmergeError.gitUnavailable) { try git.commitAll(authorName: "a", authorEmail: "a@example.com", message: "m") }
        #expect(throws: BrainmergeError.gitUnavailable) { try git.log() }
        #expect(throws: BrainmergeError.gitUnavailable) { try git.lastAuthors() }
        #expect(git.head() == nil)
        #expect(throws: BrainmergeError.gitUnavailable) {
            try Brain.initialize(at: home.paths.defaultBrain, language: .en, shell: recording, availability: missing)
        }
        #expect(calls.all.isEmpty)
        // Nothing half made: no memory folder, no BRAIN.md, no meta files for a memory that could not keep its history.
        #expect(!FileManager.default.fileExists(atPath: home.paths.defaultBrain.path))
    }
}
