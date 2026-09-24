import Darwin
import Foundation

/// Running Claude instances, recognized by their arguments (`ps`), their resident memory (instance and descendants),
/// clean shutdown via SIGTERM. A single `ps` call per round, for every account.
public struct ProcessMonitor: Sendable {
    let psOutput: @Sendable () throws -> String

    public init(shell: Shell = Shell()) {
        self.psOutput = { try shell.check("/bin/ps", ["-axo", "pid=,ppid=,rss=,args="]) }
    }

    /// For tests: a supplied `ps` output (`pid ppid rss args`).
    public init(psOutput: @escaping @Sendable () throws -> String) { self.psOutput = psOutput }

    public struct Running: Equatable, Sendable {
        public let pid: Int32
        public let ppid: Int32
        /// Resident memory of the process alone, in bytes.
        public let residentBytes: Int64
        public let arguments: String
        public init(pid: Int32, ppid: Int32, residentBytes: Int64, arguments: String) {
            self.pid = pid; self.ppid = ppid; self.residentBytes = residentBytes; self.arguments = arguments
        }
    }

    /// All the system's processes at a point in time, and the main Claude instances among them.
    public struct Snapshot: Equatable, Sendable {
        public let mains: [Running]
        public let all: [Running]
        public init(mains: [Running], all: [Running]) { self.mains = mains; self.all = all }

        /// Resident memory of an instance and all its descendants (Electron helpers, the Code tab's Claude Code).
        public func residentBytes(of pid: Int32) -> Int64 {
            var children: [Int32: [Running]] = [:]
            for p in all { children[p.ppid, default: []].append(p) }
            var total: Int64 = 0
            var queue: [Int32] = [pid]
            var seen: Set<Int32> = []
            while let current = queue.popLast() {
                guard seen.insert(current).inserted else { continue }
                if let me = all.first(where: { $0.pid == current }) { total += me.residentBytes }
                queue += (children[current] ?? []).map(\.pid)
            }
            return total
        }
    }

    public func snapshot() throws -> Snapshot { Self.snapshot(psOutput: try psOutput()) }

    /// The main instances (not the Electron helpers).
    public func claudeProcesses() throws -> [Running] { try snapshot().mains }

    static func parse(psOutput: String) -> [Running] { snapshot(psOutput: psOutput).mains }

    public static func snapshot(psOutput: String) -> Snapshot {
        var all: [Running] = []
        for line in psOutput.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let rssKB = Int64(parts[2]) else { continue }
            all.append(Running(pid: pid, ppid: ppid, residentBytes: rssKB * 1024, arguments: String(parts[3])))
        }
        let mains = all.filter { $0.arguments.contains("Contents/MacOS/Claude") && !$0.arguments.contains("Claude Helper") }
        return Snapshot(mains: mains, all: all)
    }

    /// An argument is matched whole: `Claude-perso` must not match `Claude-perso-2`.
    static func hasArgument(_ arguments: String, _ needle: String) -> Bool {
        arguments.hasSuffix(needle) || arguments.contains(needle + " ")
    }

    public static func matches(_ process: Running, identity: Identity, paths: Paths, claude: ClaudeApp) -> Bool {
        if identity.isPrimary {
            return process.arguments.hasPrefix(claude.executable.path) && !process.arguments.contains("--user-data-dir=")
        }
        return hasArgument(process.arguments, "--user-data-dir=\(identity.desktopData(in: paths).path)")
    }

    public func isRunning(identity: Identity, paths: Paths, claude: ClaudeApp) throws -> Bool {
        try claudeProcesses().contains { Self.matches($0, identity: identity, paths: paths, claude: claude) }
    }

    public func quit(identity: Identity, paths: Paths, claude: ClaudeApp) throws {
        for process in try claudeProcesses() where Self.matches(process, identity: identity, paths: paths, claude: claude) {
            kill(process.pid, SIGTERM)
        }
    }
}

/// The Mac's memory pressure, as the kernel sees it (1 normal, 2 warning, 4 critical).
public enum MemoryPressure {
    public enum Level: Int, Sendable, Comparable {
        case normal = 1, warning = 2, critical = 4
        public init(sysctlValue: Int) { self = Level(rawValue: sysctlValue) ?? (sysctlValue > 2 ? .critical : .normal) }
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public static func current() -> Level? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return nil }
        return Level(sysctlValue: Int(value))
    }

    public static var physicalMemory: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }
}
