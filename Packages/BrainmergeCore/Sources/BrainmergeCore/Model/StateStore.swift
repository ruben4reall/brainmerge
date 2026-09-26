import Foundation

public struct StateStore: Sendable {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }

    /// The file as it was before the last save: what "Restore the previous copy" puts back.
    public var previousFile: URL { paths.appSupport.appending(path: "state.previous.json") }
    /// Held around every load, change and save, by the app and the command line alike.
    public var lockFile: URL { paths.appSupport.appending(path: "state.lock") }

    public var exists: Bool { FileManager.default.fileExists(atPath: paths.stateFile.path) }

    /// A missing file is a fresh install. A file that cannot be read is never one: it throws `.stateDamaged`
    /// (or `.stateTooNew` when a newer Brainmerge wrote it), so nobody is sent back to setup with accounts on disk.
    public func load() throws -> AppState {
        guard exists else { return AppState() }
        return try read(paths.stateFile)
    }

    /// A copy from before the last change that this version can read: the only one worth putting back.
    public var canRestorePrevious: Bool { (try? read(previousFile)) != nil }

    func read(_ file: URL) throws -> AppState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data: Data
        do { data = try Data(contentsOf: file) } catch { throw BrainmergeError.stateDamaged }
        // The version is read on its own first: a newer file may not decode with this version's fields.
        struct Version: Decodable { let schemaVersion: Int }
        if let version = try? decoder.decode(Version.self, from: data), version.schemaVersion > AppState.currentSchema {
            throw BrainmergeError.stateTooNew(version.schemaVersion)
        }
        guard var state = try? decoder.decode(AppState.self, from: data) else { throw BrainmergeError.stateDamaged }
        state.schemaVersion = AppState.currentSchema
        return state
    }

    /// Atomic write: Foundation writes a temporary file then renames it. The current file is kept first as the previous copy.
    public func save(_ state: AppState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        // Only a file that still reads is worth keeping: a damaged one must not replace the good copy.
        if let current = try? Data(contentsOf: paths.stateFile), current != data, (try? load()) != nil {
            try current.write(to: previousFile, options: .atomic)
        }
        try data.write(to: paths.stateFile, options: .atomic)
    }

    /// Load, change and save under an exclusive lock on `state.lock`: the app and the command line never overwrite
    /// each other's change.
    @discardableResult
    public func update<T>(_ change: (inout AppState) throws -> T) throws -> T {
        let held = try lock()
        defer { held.release() }
        var state = try load()
        let result = try change(&state)
        try save(state)
        return result
    }

    /// An exclusive `flock` on `state.lock`, held until `release()`. Not reentrant: one holder per change.
    public func lock(timeout: TimeInterval = 10) throws -> Held {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        let fd = open(lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw BrainmergeError.lockTimeout }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if Date() >= deadline { close(fd); throw BrainmergeError.lockTimeout }
            usleep(20_000)
        }
        return Held(fd: fd)
    }

    public struct Held: Sendable {
        let fd: Int32
        public func release() { flock(fd, LOCK_UN); close(fd) }
    }

    /// Puts the previous copy back in place of an unreadable file, under the lock, only when this version can read it.
    /// The unreadable one is kept beside it, never deleted, and the swap is atomic: no reader ever finds no file (a fresh
    /// install) in between.
    public func restorePrevious() throws {
        let held = try lock()
        defer { held.release() }
        guard canRestorePrevious else { throw BrainmergeError.stateDamaged }
        let fm = FileManager.default
        if exists {
            let aside = paths.appSupport.appending(path: "state.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            if !fm.fileExists(atPath: aside.path) { try fm.copyItem(at: paths.stateFile, to: aside) }
        }
        try Data(contentsOf: previousFile).write(to: paths.stateFile, options: .atomic)
    }
}
