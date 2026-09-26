import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// How an account's last save went, written by the Stop hook for the app: codes only, from a closed list.
@Suite struct SaveStatusTests {
    /// Each error a save can meet becomes one reason of the closed list; anything else is "unknown".
    @Test func errorsMapToTheirReason() {
        let cases: [(Error, SaveStatus.Reason)] = [
            (BrainmergeError.lockTimeout, .locked),
            (BrainmergeError.gitOperationUnfinished, .locked),
            (BrainmergeError.shellFailed(command: "/usr/bin/git commit", status: 128,
                                         stderr: "fatal: Unable to create '/Users/x/Brain/.git/index.lock': File exists."), .locked),
            // A save commits through its own index: the lock it meets is the branch's.
            (BrainmergeError.shellFailed(command: "/usr/bin/git commit", status: 128,
                                         stderr: "fatal: cannot lock ref 'HEAD': Unable to create '/Users/x/Brain/.git/refs/heads/main.lock': File exists."), .locked),
            (BrainmergeError.shellFailed(command: "/usr/bin/git update-ref", status: 128,
                                         stderr: "fatal: Unable to create '/Users/x/Brain/.git/HEAD.lock': File exists."), .locked),
            (BrainmergeError.gitUnavailable, .gitMissing),
            (BrainmergeError.shellFailed(command: "/usr/bin/git add", status: 1,
                                         stderr: "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)"), .gitMissing),
            (BrainmergeError.shellFailed(command: "/usr/bin/git commit", status: 128,
                                         stderr: "error: unable to write new index file: No space left on device"), .diskFull),
            (CocoaError(.fileWriteOutOfSpace), .diskFull),
            (POSIXError(.ENOSPC), .diskFull),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .diskFull),
            (BrainmergeError.shellFailed(command: "/usr/bin/git status", status: 128,
                                         stderr: "fatal: not a git repository (or any of the parent directories): .git"), .notARepository),
            (BrainmergeError.brainNotFound("/Users/x/Brain"), .notARepository),
            (BrainmergeError.brainNotConfigured, .notARepository),
            (BrainmergeError.shellFailed(command: "/usr/bin/git commit", status: 1, stderr: "error: something else"), .unknown),
            (BrainmergeError.stateDamaged, .unknown),
            (CocoaError(.fileWriteNoPermission), .unknown),
        ]
        for (error, reason) in cases {
            #expect(SaveStatus.Reason(error) == reason, "\(error)")
        }
    }

    /// Written and read back per account, in Application Support: the date, the outcome and the reason, nothing else.
    @Test func isWrittenPerAccountAndReadBack() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = SaveStatusStore(paths: home.paths)
        #expect(store.read(slug: "work") == nil)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        store.write(SaveStatus(date: date, outcome: .failed, reason: .locked), slug: "work")
        #expect(store.read(slug: "work") == SaveStatus(date: date, outcome: .failed, reason: .locked))
        #expect(FileManager.default.fileExists(atPath: home.paths.appSupport.appending(path: "saves/work.json").path))
        store.write(SaveStatus(date: date, outcome: .committed), slug: "work")
        #expect(store.read(slug: "work")?.outcome == .committed)
        #expect(store.read(slug: "work")?.reason == nil)
        #expect(store.read(slug: "perso") == nil)
    }

    /// The account's name comes from the hook's command line: anything that is not a slug never names a file.
    @Test func onlyASlugNamesAFile() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = SaveStatusStore(paths: home.paths)
        for bad in ["", "../escape", "a/b", ".hidden", "Work", "work.json", String(repeating: "a", count: 65)] {
            store.write(SaveStatus(date: Date(), outcome: .failed, reason: .unknown), slug: bad)
            #expect(store.read(slug: bad) == nil, "\(bad)")
        }
        #expect(!FileManager.default.fileExists(atPath: home.url.appending(path: "Library/Application Support/escape.json").path))
        let saves = home.paths.appSupport.appending(path: "saves")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: saves.path)) ?? []).isEmpty)
        store.write(SaveStatus(date: Date(), outcome: .nothing), slug: "client-2")
        #expect(store.read(slug: "client-2")?.outcome == .nothing)
    }

    /// An unreadable file reads as no status: the app shows nothing rather than a guess.
    @Test func anUnreadableFileIsNoStatus() throws {
        let home = try TempHome(); defer { home.remove() }
        let store = SaveStatusStore(paths: home.paths)
        let file = home.paths.appSupport.appending(path: "saves/work.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: file)
        #expect(store.read(slug: "work") == nil)
        try Data(#"{"date":"2026-09-26T10:00:00Z","outcome":"exploded"}"#.utf8).write(to: file)
        #expect(store.read(slug: "work") == nil)
    }

    /// Codes only: the file can never carry a path, a note's name or an error's words.
    @Test func holdsCodesOnly() throws {
        let status = SaveStatus(date: Date(), outcome: .failed, reason: .diskFull)
        #expect(Mirror(reflecting: status).children.map(\.label) == ["date", "outcome", "reason"])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        #expect(Set(json.keys) == ["date", "outcome", "reason"])
        #expect(SaveStatus.Outcome.allCases.map(\.rawValue) == ["committed", "nothing", "failed", "held"])
        #expect(SaveStatus.Reason.allCases.map(\.rawValue) == ["locked", "gitMissing", "diskFull", "notARepository", "heldBack", "unknown"])
    }
}
