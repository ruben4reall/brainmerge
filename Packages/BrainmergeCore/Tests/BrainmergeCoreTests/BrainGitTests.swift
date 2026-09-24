import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct BrainGitTests {
    @Test func commitRecordsIdentityAsAuthorAndLogListsFiles() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        #expect(try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Init") == true)
        #expect(try git.commitAll(authorName: "Setup", authorEmail: "setup@brainmerge.local", message: "Init") == false)

        let dir = brain.memoryDir(forProject: "atelier")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# x\n".utf8).write(to: dir.appending(path: "MEMORY.md"))
        #expect(try git.commitAll(authorName: "ClientStudio", authorEmail: "client@brainmerge.local",
                                  message: "Brain update by ClientStudio") == true)

        let log = try git.log(limit: 10)
        #expect(log.count == 2)
        #expect(log[0].authorName == "ClientStudio")
        #expect(log[0].authorEmail == "client@brainmerge.local")
        #expect(log[0].message == "Brain update by ClientStudio")
        #expect(log[0].files == ["memory/atelier/MEMORY.md"])
        #expect(log[1].files.contains("BRAIN.md"))
        #expect(abs(log[0].date.timeIntervalSinceNow) < 60)
    }

    @Test func logOnRepositoryWithoutCommitsIsEmpty() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        #expect(try BrainGit(brain: brain).log().isEmpty)
        #expect(try BrainGit(brain: brain).hasChanges())
    }

    @Test func lockBlocksOtherHoldersUntilReleased() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let git = BrainGit(brain: brain)
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try? git.withLock(timeout: 2) { acquired.signal(); release.wait() }
        }
        acquired.wait()
        #expect(throws: BrainmergeError.lockTimeout) { try git.withLock(timeout: 0.3) { } }
        release.signal()
        Thread.sleep(forTimeInterval: 0.3)
        #expect(try git.withLock(timeout: 1) { 42 } == 42)
    }
}
