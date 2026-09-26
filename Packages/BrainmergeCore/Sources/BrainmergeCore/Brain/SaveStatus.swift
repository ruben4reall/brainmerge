import Foundation

/// How an account's last save went (its Stop hook, see Sync), for the app to show when saves stop: the date, the outcome
/// and a reason from a closed list. Codes only: never a path, a note's name or an error's words.
public struct SaveStatus: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable, CaseIterable { case committed, nothing, failed, held }

    public enum Reason: String, Codable, Sendable, CaseIterable {
        case locked, gitMissing, diskFull, notARepository, heldBack, unknown

        /// The reason an error stands for. Git's own words are only looked at here, never kept.
        public init(_ error: Error) {
            switch error {
            case BrainmergeError.lockTimeout, BrainmergeError.gitOperationUnfinished: self = .locked
            case BrainmergeError.gitUnavailable: self = .gitMissing
            case BrainmergeError.brainNotFound, BrainmergeError.brainNotConfigured: self = .notARepository
            case BrainmergeError.shellFailed(_, _, let stderr): self = Self(gitSaid: stderr)
            case let error as CocoaError where error.code == .fileWriteOutOfSpace: self = .diskFull
            case let error as POSIXError where error.code == .ENOSPC: self = .diskFull
            case let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC): self = .diskFull
            default: self = .unknown
            }
        }

        private init(gitSaid stderr: String) {
            if stderr.contains("No space left on device") { self = .diskFull }
            else if stderr.contains("not a git repository") { self = .notARepository }
            // Apple's stub in /usr/bin/git without the Command Line Tools.
            else if stderr.contains("invalid active developer path") { self = .gitMissing }
            // Another git (an editor's, the person's) holds the memory's index.
            else if stderr.contains("index.lock") { self = .locked }
            else { self = .unknown }
        }
    }

    public let date: Date
    public let outcome: Outcome
    public let reason: Reason?
    public init(date: Date, outcome: Outcome, reason: Reason? = nil) { self.date = date; self.outcome = outcome; self.reason = reason }
}

/// `~/Library/Application Support/Brainmerge/saves/<account>.json`, one file per account, replaced by each save.
public struct SaveStatusStore: Sendable {
    public let directory: URL
    public init(paths: Paths) { directory = paths.appSupport.appending(path: "saves", directoryHint: .isDirectory) }

    /// Only a slug names a file (lowercase letters, digits and dashes): the name comes from the hook's command line.
    func file(slug: String) -> URL? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard (1...64).contains(slug.count), slug.allSatisfy(allowed.contains), !slug.hasPrefix("-") else { return nil }
        return directory.appending(path: "\(slug).json")
    }

    /// Never fails a save: a status that cannot be written is only missing.
    public func write(_ status: SaveStatus, slug: String) {
        guard let file = file(slug: slug) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(status) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Nil when there is none, or when it cannot be read.
    public func read(slug: String) -> SaveStatus? {
        guard let file = file(slug: slug), let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SaveStatus.self, from: data)
    }
}
