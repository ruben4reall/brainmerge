import Foundation

public struct ShellResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public struct Shell: Sendable {
    public init() {}

    /// Runs a program and captures its output. stderr goes through a temporary file:
    /// no risk of a deadlock when both streams are large.
    @discardableResult
    public func run(_ executable: String, _ arguments: [String], cwd: URL? = nil,
                    environment: [String: String]? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
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
