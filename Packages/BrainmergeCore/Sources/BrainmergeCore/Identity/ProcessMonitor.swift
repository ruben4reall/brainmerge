import Darwin
import Foundation

/// Running Claude instances, recognized by their arguments (`ps`), the RAM they use (instance and descendants),
/// clean shutdown via SIGTERM. A single `ps` call per round, for every account.
///
/// `ps` stays the only source of arguments: it never shows another process's environment, which can hold API keys,
/// whereas the kernel's argument call (KERN_PROCARGS2) returns both together.
public struct ProcessMonitor: Sendable {
    let psOutput: @Sendable () throws -> String
    let footprint: @Sendable (Int32) -> Int64?

    public init(shell: Shell = Shell()) {
        self.psOutput = { try shell.check("/bin/ps", ["-axo", "pid=,ppid=,rss=,args="]) }
        self.footprint = { ProcessMonitor.footprint(of: $0) }
    }

    /// For tests: a supplied `ps` output (`pid ppid rss args`). No footprint by default, so a fake pid that happens to
    /// exist on the test Mac never brings in a real process's number.
    public init(psOutput: @escaping @Sendable () throws -> String, footprint: @escaping @Sendable (Int32) -> Int64? = { _ in nil }) {
        self.psOutput = psOutput
        self.footprint = footprint
    }

    public struct Running: Equatable, Sendable {
        public let pid: Int32
        public let ppid: Int32
        /// Resident memory of the process alone, in bytes.
        public let residentBytes: Int64
        /// Empty for a process that is not Claude's (see `snapshot(psOutput:)`).
        public let arguments: String
        public init(pid: Int32, ppid: Int32, residentBytes: Int64, arguments: String) {
            self.pid = pid; self.ppid = ppid; self.residentBytes = residentBytes; self.arguments = arguments
        }
    }

    /// Claude Code started outside any Claude window: how many sessions, and the RAM of their trees together.
    public struct TerminalUse: Equatable, Sendable {
        public var sessions: Int
        public var bytes: Int64
        public init(sessions: Int, bytes: Int64) { self.sessions = sessions; self.bytes = bytes }
    }

    /// All the system's processes at a point in time, and the main Claude instances among them.
    public struct Snapshot: Equatable, Sendable {
        public let mains: [Running]
        public let all: [Running]
        /// phys_footprint per pid, for Claude's processes only, when the snapshot was measured.
        public let footprints: [Int32: Int64]
        public init(mains: [Running], all: [Running], footprints: [Int32: Int64] = [:]) {
            self.mains = mains; self.all = all; self.footprints = footprints
        }

        /// The RAM an instance and all its descendants use (Electron helpers, the Code tab's Claude Code), as Activity
        /// Monitor shows it: each process's footprint, or its resident size when the kernel gave none (it exited, it is
        /// not ours to ask, or the snapshot was not measured).
        public func memoryBytes(of pid: Int32) -> Int64 {
            tree(of: pid).reduce(0) { $0 + (footprints[$1.pid] ?? $1.residentBytes) }
        }

        /// Claude Code sessions with no Claude window above them and no other session above them (those are their
        /// tools): nothing in their arguments says which account they use, and their environment is never read.
        public var terminalSessions: [Running] {
            let byPid = Dictionary(all.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
            let windows = Set(mains.map(\.pid))
            return all.filter { process in
                guard ProcessMonitor.isClaudeCode(arguments: process.arguments) else { return false }
                var seen: Set<Int32> = [process.pid]
                var parent = process.ppid
                while let above = byPid[parent], seen.insert(above.pid).inserted {
                    if windows.contains(above.pid) || ProcessMonitor.isClaudeCode(arguments: above.arguments) { return false }
                    parent = above.ppid
                }
                return true
            }
        }

        public var terminalUse: TerminalUse {
            let sessions = terminalSessions
            let windows = Set(mains.map(\.pid))
            let bytes = sessions.reduce(Int64(0)) { total, session in
                total + tree(of: session.pid, stoppingAt: windows).reduce(0) { $0 + (footprints[$1.pid] ?? $1.residentBytes) }
            }
            return TerminalUse(sessions: sessions.count, bytes: bytes)
        }

        /// Every process in a Claude window's tree or a terminal session's tree: the only ones measuring asks about.
        var claudePids: Set<Int32> {
            let roots = mains.map(\.pid) + terminalSessions.map(\.pid)
            return Set(roots.flatMap { tree(of: $0).map(\.pid) })
        }

        /// A process and its descendants through their parent pid; a Claude window found below a terminal session
        /// (`stoppingAt`) is its account's, not counted twice.
        func tree(of pid: Int32, stoppingAt stops: Set<Int32> = []) -> [Running] {
            var children: [Int32: [Running]] = [:]
            for p in all { children[p.ppid, default: []].append(p) }
            var found: [Running] = []
            if let root = all.first(where: { $0.pid == pid }) { found.append(root) }
            var queue: [Int32] = [pid]
            var seen: Set<Int32> = []
            while let current = queue.popLast() {
                guard seen.insert(current).inserted else { continue }
                for child in children[current] ?? [] where !stops.contains(child.pid) && !seen.contains(child.pid) {
                    found.append(child)
                    queue.append(child.pid)
                }
            }
            return found
        }
    }

    /// `measuring`: also asks the kernel for the footprint of every process in Claude's trees (a few dozen calls),
    /// for the RAM figures. Checking what runs, or quitting, does not need it.
    public func snapshot(measuring: Bool = false) throws -> Snapshot {
        let plain = Self.snapshot(psOutput: try psOutput())
        guard measuring else { return plain }
        var footprints: [Int32: Int64] = [:]
        for pid in plain.claudePids { if let bytes = footprint(pid) { footprints[pid] = bytes } }
        return Snapshot(mains: plain.mains, all: plain.all, footprints: footprints)
    }

    /// Activity Monitor's "Memory" column for one process (phys_footprint): it counts GPU and IOKit memory, which the
    /// resident size misses, and pages shared between Electron processes once. Nil for a process that exited or is not ours.
    public static func footprint(of pid: Int32) -> Int64? {
        var info = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
        }
        guard result == 0 else { return nil }
        return Int64(clamping: info.ri_phys_footprint)
    }

    /// Claude Code, however it was started: its native binary from PATH or by path, or its npm package run by node or bun.
    /// The first word is the program: a Claude Code whose own path holds a space is only recognized under a Claude
    /// window, where the tree finds it anyway.
    public static func isClaudeCode(arguments: String) -> Bool {
        if arguments.contains("@anthropic-ai/claude-code/") { return true }
        let words = arguments.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard let first = words.first else { return false }
        func name(_ word: Substring) -> Substring { word.split(separator: "/").last ?? word }
        if name(first) == "claude" { return true }
        if ["node", "bun"].contains(name(first)), words.count > 1 { return name(words[1]) == "claude" }
        return false
    }

    /// The main instances (not the Electron helpers).
    public func claudeProcesses() throws -> [Running] { try snapshot().mains }

    static func parse(psOutput: String) -> [Running] { snapshot(psOutput: psOutput).mains }

    public static func snapshot(psOutput: String) -> Snapshot {
        var all: [Running] = []
        for line in psOutput.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let rssKB = Int64(parts[2]) else { continue }
            // Only a command line that mentions Claude is kept: any other program's arguments can hold a key.
            let arguments = parts[3].range(of: "claude", options: .caseInsensitive) == nil ? "" : String(parts[3])
            all.append(Running(pid: pid, ppid: ppid, residentBytes: rssKB * 1024, arguments: arguments))
        }
        let mains = all.filter { $0.arguments.contains("Contents/MacOS/Claude") && !$0.arguments.contains("Claude Helper") }
        return Snapshot(mains: mains, all: all)
    }

    /// For tests: a snapshot with the footprints the kernel would have given.
    public static func snapshot(psOutput: String, footprints: [Int32: Int64]) -> Snapshot {
        let plain = snapshot(psOutput: psOutput)
        return Snapshot(mains: plain.mains, all: plain.all, footprints: footprints)
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
