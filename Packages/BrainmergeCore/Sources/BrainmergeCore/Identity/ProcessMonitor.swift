import Darwin
import Foundation

/// Running Claude instances, recognized by their arguments (`ps`), the RAM they use (instance and descendants),
/// clean shutdown via SIGTERM. A single `ps` call per round, for every account.
///
/// `ps` stays the only source of arguments: it never shows another process's environment, which can hold API keys,
/// whereas the kernel's argument call (KERN_PROCARGS2) returns both together.
public struct ProcessMonitor: Sendable {
    let psOutput: @Sendable () throws -> String
    /// One kernel call per process: its footprint and when it started (see `usage(of:)`). `measuring`: the footprint is
    /// wanted too.
    let usage: @Sendable (_ pid: Int32, _ measuring: Bool) -> Usage

    /// What one kernel call says of a process: Activity Monitor's "Memory" and its start in mach absolute time.
    public struct Usage: Equatable, Sendable {
        public var footprint: Int64?
        public var startAbstime: UInt64?
        public init(footprint: Int64? = nil, startAbstime: UInt64? = nil) { self.footprint = footprint; self.startAbstime = startAbstime }
    }

    public init(shell: Shell = Shell()) {
        self.psOutput = { try shell.check("/bin/ps", ["-axo", "pid=,ppid=,rss=,args="]) }
        self.usage = { pid, _ in ProcessMonitor.usage(of: pid) ?? Usage() }
    }

    /// For tests: a supplied `ps` output (`pid ppid rss args`). No footprint by default, so a fake pid that happens to
    /// exist on the test Mac never brings in a real process's number.
    public init(psOutput: @escaping @Sendable () throws -> String, footprint: @escaping @Sendable (Int32) -> Int64? = { _ in nil },
                startTime: @escaping @Sendable (Int32) -> UInt64? = { _ in nil }) {
        self.psOutput = psOutput
        self.usage = { pid, measuring in Usage(footprint: measuring ? footprint(pid) : nil, startAbstime: startTime(pid)) }
    }

    /// For tests: a supplied `ps` output and what the kernel would say of each process, asked once per process.
    init(psOutput: @escaping @Sendable () throws -> String, usage: @escaping @Sendable (Int32) -> Usage) {
        self.psOutput = psOutput
        self.usage = { pid, _ in usage(pid) }
    }

    /// A process as `ps` shows it, reduced to what the monitor needs. Its command line is read once, when the process is
    /// made, and never kept: any program's arguments can hold a key, Claude Code's own (a session started with
    /// `--settings`) and the Bash commands it runs (`zsh -c source ~/.claude/shell-snapshots/… && eval '…'`) included.
    public struct Running: Equatable, Sendable {
        public let pid: Int32
        public let ppid: Int32
        /// Resident memory of the process alone, in bytes.
        public let residentBytes: Int64
        /// Claude's app itself, not a helper: the program it runs, up to its `Contents/MacOS/Claude…` name. Nil for every
        /// other process.
        public let claudeProgram: String?
        /// The folder a Claude window was given with `--user-data-dir=`, up to its next `--` flag: nil for the first
        /// account's Claude and for every process that is not a Claude window.
        public let userDataDir: String?
        /// Claude Code, however it was started (see `isClaudeCode(arguments:)`).
        public let isClaudeCode: Bool
        /// Runs from a `claude-code` folder: the Code tab's Claude Code, whose own path holds a space.
        public let runsFromClaudeCodeFolder: Bool
        /// When it started, in mach absolute time (main instances only; nil when not asked or not given).
        public var startAbstime: UInt64?

        /// Takes what the monitor needs from `commandLine` and lets the line go. A shell's line (`zsh -c …`) is never
        /// Claude's, whatever it mentions.
        public init(pid: Int32, ppid: Int32, residentBytes: Int64, commandLine: some StringProtocol, startAbstime: UInt64? = nil) {
            self.pid = pid; self.ppid = ppid; self.residentBytes = residentBytes; self.startAbstime = startAbstime
            let line = String(commandLine)
            guard line.range(of: "claude", options: .caseInsensitive) != nil, !ProcessMonitor.isShell(line) else {
                claudeProgram = nil; userDataDir = nil; isClaudeCode = false; runsFromClaudeCodeFolder = false
                return
            }
            let program = ProcessMonitor.claudeProgram(line)
            claudeProgram = program
            userDataDir = program == nil ? nil : ProcessMonitor.userDataDir(line)
            isClaudeCode = ProcessMonitor.isClaudeCode(arguments: line)
            runsFromClaudeCodeFolder = line.contains("/claude-code/")
        }

        /// A Claude window: Claude's app itself, not one of its helpers.
        public var isClaudeWindow: Bool { claudeProgram != nil }
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
                guard process.isClaudeCode else { return false }
                var seen: Set<Int32> = [process.pid]
                var parent = process.ppid
                while let above = byPid[parent], seen.insert(above.pid).inserted {
                    if windows.contains(above.pid) || above.isClaudeCode { return false }
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

        /// Claude Code sessions below this window (the Code tab, or a terminal started from it); a session's own tools
        /// that are Claude Code too are not counted again.
        public func claudeCodeSessions(under pid: Int32) -> Int {
            // The Code tab's own Claude Code lives in the data folder, whose path holds a space: its folder name tells it.
            func isCode(_ p: Running) -> Bool { p.isClaudeCode || p.runsFromClaudeCodeFolder }
            let nodes = tree(of: pid).filter { $0.pid != pid }
            let codePids = Set(nodes.filter(isCode).map(\.pid))
            return nodes.filter { isCode($0) && !codePids.contains($0.ppid) }.count
        }

        public func hasClaudeCode(under pid: Int32) -> Bool { claudeCodeSessions(under: pid) > 0 }

        /// A Claude Code session of any account runs, in a terminal or in a window's Code tab: it may be writing notes
        /// without an edit tool, so the person's own edits wait (see OwnEdits).
        public var hasClaudeCodeSession: Bool {
            all.contains { $0.isClaudeCode || $0.runsFromClaudeCodeFolder }
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
        // One kernel call per process: the windows always (their start tells a window older than Claude's update), and
        // every process of Claude's trees when measuring, a window's footprint coming from the call that gave its start.
        let windows = Set(plain.mains.map(\.pid))
        var asked: [Int32: Usage] = [:]
        for pid in measuring ? plain.claudePids.union(windows) : windows { asked[pid] = usage(pid, measuring) }
        let mains = plain.mains.map { var main = $0; main.startAbstime = asked[$0.pid]?.startAbstime; return main }
        guard measuring else { return Snapshot(mains: mains, all: plain.all) }
        return Snapshot(mains: mains, all: plain.all, footprints: asked.compactMapValues(\.footprint))
    }

    /// Activity Monitor's "Memory" column for one process (phys_footprint): it counts GPU and IOKit memory, which the
    /// resident size misses, and pages shared between Electron processes once. Nil for a process that exited or is not ours.
    public static func footprint(of pid: Int32) -> Int64? { usage(of: pid)?.footprint }

    /// A process's footprint and its start in mach absolute time (ri_proc_start_abstime), from one call for the smallest
    /// record that holds both. Nil for a process that exited or is not ours.
    public static func usage(of pid: Int32) -> Usage? {
        var info = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
        }
        guard result == 0 else { return nil }
        return Usage(footprint: Int64(clamping: info.ri_phys_footprint), startAbstime: info.ri_proc_start_abstime)
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
            all.append(Running(pid: pid, ppid: ppid, residentBytes: rssKB * 1024, commandLine: parts[3]))
        }
        return Snapshot(mains: all.filter(\.isClaudeWindow), all: all)
    }

    /// Shells, by their program's name (a login shell's starts with "-"): what they run is their own command line, and
    /// Claude Code's Bash commands name its folders.
    static let shells: Set<Substring> = ["sh", "bash", "zsh", "dash", "ksh", "mksh", "fish", "tcsh", "csh"]

    static func isShell(_ commandLine: String) -> Bool {
        guard let first = commandLine.split(separator: " ", maxSplits: 1).first else { return false }
        let name = first.split(separator: "/").last ?? first
        return shells.contains(name.hasPrefix("-") ? name.dropFirst() : name)
    }

    /// Claude's app itself (not a helper): its program, up to the end of its `Contents/MacOS/Claude…` name.
    static func claudeProgram(_ commandLine: String) -> String? {
        guard !commandLine.contains("Claude Helper"), let name = commandLine.range(of: "Contents/MacOS/Claude") else { return nil }
        let end = commandLine[name.upperBound...].firstIndex(of: " ") ?? commandLine.endIndex
        return String(commandLine[..<end])
    }

    /// The value of `--user-data-dir=`, up to the next `--` flag: a folder's path can hold spaces.
    static func userDataDir(_ commandLine: String) -> String? {
        guard let flag = commandLine.range(of: "--user-data-dir=") else { return nil }
        let rest = commandLine[flag.upperBound...]
        return String(rest[..<(rest.range(of: " --")?.lowerBound ?? rest.endIndex)])
    }

    /// For tests: a snapshot with the footprints the kernel would have given.
    public static func snapshot(psOutput: String, footprints: [Int32: Int64]) -> Snapshot {
        let plain = snapshot(psOutput: psOutput)
        return Snapshot(mains: plain.mains, all: plain.all, footprints: footprints)
    }

    /// A Claude window is an account's when its folder is the account's, matched whole: `Claude-perso` must not match
    /// `Claude-perso-2`. The first account's Claude is Claude itself, with no folder given.
    public static func matches(_ process: Running, identity: Identity, paths: Paths, claude: ClaudeApp) -> Bool {
        guard let program = process.claudeProgram else { return false }
        guard let folder = process.userDataDir else { return identity.isPrimary && program == claude.executable.path }
        let wanted = identity.desktopData(in: paths).path
        return !identity.isPrimary && (folder == wanted || folder.hasPrefix(wanted + " "))
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
