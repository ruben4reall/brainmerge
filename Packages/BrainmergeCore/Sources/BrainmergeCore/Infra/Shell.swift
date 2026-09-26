import Foundation

public struct ShellResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public init(status: Int32, stdout: String, stderr: String) { self.status = status; self.stdout = stdout; self.stderr = stderr }
}

public struct Shell: Sendable {
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String], _ cwd: URL?, _ environment: [String: String]?) throws -> ShellResult
    /// Stands in for `run` in tests (a fake that records calls or fails on purpose). Nil runs the real program.
    let runner: Runner?
    /// Brainmerge's own environment, which a program started here is given (see `run`). Only tests set it, to stand for
    /// the environment a session gives a hook.
    let inherited: [String: String]?
    /// How long a git call may take before it is stopped (see `run`).
    let gitTimeout: TimeInterval
    public init() { runner = nil; inherited = nil; gitTimeout = 120 }
    public init(runner: @escaping Runner) { self.runner = runner; inherited = nil; gitTimeout = 120 }
    init(inheriting inherited: [String: String]?, gitTimeout: TimeInterval = 120) {
        runner = nil; self.inherited = inherited; self.gitTimeout = gitTimeout
    }

    /// Runs a program and captures its output. stderr goes through a temporary file:
    /// no risk of a deadlock when both streams are large. Git runs apart from the person's own git (see `gitEnvironment`),
    /// with no input, and is stopped after `gitTimeout`.
    @discardableResult
    public func run(_ executable: String, _ arguments: [String], cwd: URL? = nil,
                    environment: [String: String]? = nil) throws -> ShellResult {
        if let runner { return try runner(executable, arguments, cwd, environment) }
        if URL(fileURLWithPath: executable).lastPathComponent == "git" {
            return try runIsolated(executable, arguments, cwd: cwd,
                                   environment: Self.gitEnvironment(inherited ?? ProcessInfo.processInfo.environment, environment),
                                   timeout: gitTimeout)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        if environment != nil || inherited != nil {
            process.environment = (inherited ?? ProcessInfo.processInfo.environment).merging(environment ?? [:]) { $1 }
        }
        let stdoutPipe = Pipe()
        let stderrFile = FileManager.default.temporaryDirectory
            .appending(path: "brainmerge-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrFile)
        defer { try? stderrHandle.close(); try? FileManager.default.removeItem(at: stderrFile) }
        process.standardOutput = stdoutPipe
        process.standardError = stderrHandle
        try process.run()
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errData = (try? Data(contentsOf: stderrFile)) ?? Data()
        return ShellResult(status: process.terminationStatus,
                           stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errData, as: UTF8.self))
    }

    /// What git is given: Brainmerge's own environment without git's variables (GIT_DIR, GIT_INDEX_FILE, GIT_AUTHOR_NAME
    /// and the like, which a session may carry), then `environment` (a save's own index). No system or global config
    /// (signing, a hook folder, templates), and no hook, signing or file monitor even where the memory's own config asks
    /// for them: a save must never prompt, run the person's programs or be refused by them.
    static func gitEnvironment(_ inherited: [String: String], _ environment: [String: String]?) -> [String: String] {
        var result = inherited.filter { !$0.key.hasPrefix("GIT_") }
        result["GIT_CONFIG_NOSYSTEM"] = "1"
        result["GIT_CONFIG_GLOBAL"] = "/dev/null"
        let settings = [("core.hooksPath", "/dev/null"), ("commit.gpgSign", "false"), ("core.fsmonitor", "false")]
        result["GIT_CONFIG_COUNT"] = String(settings.count)
        for (index, (key, value)) in settings.enumerated() {
            result["GIT_CONFIG_KEY_\(index)"] = key
            result["GIT_CONFIG_VALUE_\(index)"] = value
        }
        return result.merging(environment ?? [:]) { $1 }
    }

    /// Runs a program with exactly `environment`, nothing inherited from Brainmerge's own (an environment can hold keys),
    /// no input, and stops it once `timeout` has passed. Both streams are read while it runs and kept in memory only.
    /// Used to ask Claude Code something on a click (see `ClaudeCodeLimits`), and for every git call (see `run`).
    public func runIsolated(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String],
                            timeout: TimeInterval) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        process.environment = environment
        // No input: a program that reads its input when it is not a terminal must not wait on Brainmerge's.
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let out = StreamReader(outPipe), err = StreamReader(errPipe)
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
            out.stop(); err.stop()
            throw BrainmergeError.timedOut(command: ([executable] + arguments).joined(separator: " "))
        }
        // A program it started may still hold the streams open: what came so far is enough.
        let stdout = out.finish(within: 2), stderr = err.finish(within: 2)
        return ShellResult(status: process.terminationStatus,
                           stdout: String(decoding: stdout, as: UTF8.self),
                           stderr: String(decoding: stderr, as: UTF8.self))
    }

    /// Collects a pipe's bytes as they come, without blocking a thread on it.
    private final class StreamReader: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()
        private var data = Data()
        private let ended = DispatchSemaphore(value: 0)

        init(_ pipe: Pipe) {
            handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    self.ended.signal()
                } else {
                    self.lock.lock(); self.data.append(chunk); self.lock.unlock()
                }
            }
        }

        func stop() { handle.readabilityHandler = nil }

        func finish(within seconds: TimeInterval) -> Data {
            _ = ended.wait(timeout: .now() + seconds)
            stop()
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    /// Like `run`, but fails if the exit code isn't 0.
    @discardableResult
    public func check(_ executable: String, _ arguments: [String], cwd: URL? = nil,
                      environment: [String: String]? = nil) throws -> String {
        let r = try run(executable, arguments, cwd: cwd, environment: environment)
        guard r.status == 0 else {
            throw BrainmergeError.shellFailed(command: ([executable] + arguments).joined(separator: " "),
                                              status: r.status, stderr: r.stderr)
        }
        return r.stdout
    }
}
