import Foundation

/// `~/Library/Logs/Brainmerge/sync.log`: what the hooks did, one line each. Several hooks write at once (two accounts'
/// Stop hooks, a SessionStart link): each line goes in one append, never over another's. Past `limit` bytes the log moves
/// to `sync.log.1`, replacing the one before, so it never grows for good.
public struct SyncLog: Sendable {
    public let file: URL
    let limit: Int
    public init(paths: Paths, limit: Int = 1_000_000) {
        file = paths.logsDir.appending(path: "sync.log")
        self.limit = limit
    }

    /// Never fails a hook: a line that cannot be written is only missing.
    public func write(_ line: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8)
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        // Held for the size check and the move, so two writers never both move the log.
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        var info = stat()
        if fstat(fd, &info) == 0, Int(info.st_size) >= limit, info.st_nlink > 0 {
            _ = rename(file.path, file.path + ".1")
            let fresh = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o644)
            guard fresh >= 0 else { return }
            defer { close(fresh) }
            _ = data.withUnsafeBytes { Darwin.write(fresh, $0.baseAddress, $0.count) }
            return
        }
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    }
}
