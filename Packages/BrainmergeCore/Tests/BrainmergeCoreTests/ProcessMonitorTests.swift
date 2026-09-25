import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ProcessMonitorTests {
    // Output of `ps -axo pid=,ppid=,rss=,args=`: pid, parent, resident memory in KB, arguments.
    let ps = """
      401 1 100000 /Applications/Claude.app/Contents/MacOS/Claude
      402 401 700000 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer
      403 1 120000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/r/Library/Application Support/Claude-client
      404 1 110000 /Users/r/Applications/Brainmerge/Client (Claude).app/Contents/MacOS/Claude-bin --user-data-dir=/Users/r/Library/Application Support/Claude-client
      405 1 5000 /usr/bin/vim notes.md
      406 1 130000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/r/Library/Application Support/Claude-client-2
      407 403 300000 /Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app/Contents/MacOS/Claude Helper (GPU) --type=gpu-process
      408 407 50000 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility
      409 403 200000 /Users/r/Library/Application Support/Claude-client/claude-code/2.1.280/claude
    """

    @Test func parsesClaudeProcessesOnly() {
        let running = ProcessMonitor.parse(psOutput: ps)
        #expect(running.map(\.pid) == [401, 403, 404, 406])
    }

    @Test func matchesPrimaryAndSecondaryIdentities() throws {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/r"))
        let claude = ClaudeApp(url: URL(fileURLWithPath: "/Applications/Claude.app"), version: "2.7032.0",
                               bundleIdentifier: ClaudeApp.bundleIdentifier)
        let running = ProcessMonitor.parse(psOutput: ps)
        let primary = Identity(slug: "perso", name: "Perso", isPrimary: true)
        let client = Identity(slug: "client", name: "Client")
        let other = Identity(slug: "work", name: "Work")
        #expect(running.filter { ProcessMonitor.matches($0, identity: primary, paths: paths, claude: claude) }.map(\.pid) == [401])
        #expect(running.filter { ProcessMonitor.matches($0, identity: client, paths: paths, claude: claude) }.map(\.pid) == [403, 404])
        #expect(running.filter { ProcessMonitor.matches($0, identity: other, paths: paths, claude: claude) }.isEmpty)
        let client2 = Identity(slug: "client-2", name: "Client 2")
        #expect(running.filter { ProcessMonitor.matches($0, identity: client2, paths: paths, claude: claude) }.map(\.pid) == [406])
    }

    @Test func memorySumsAnInstanceAndItsDescendantsOnly() {
        let snapshot = ProcessMonitor.snapshot(psOutput: ps)
        #expect(snapshot.mains.map(\.pid) == [401, 403, 404, 406])
        #expect(snapshot.all.count == 9)
        // 403 plus its GPU (407) plus the GPU utility (408) plus its Claude Code (409), nothing from the other instances.
        #expect(snapshot.memoryBytes(of: 403) == Int64(120_000 + 300_000 + 50_000 + 200_000) * 1024)
        #expect(snapshot.memoryBytes(of: 401) == Int64(100_000 + 700_000) * 1024)
        #expect(snapshot.memoryBytes(of: 406) == Int64(130_000) * 1024)
    }

    // MARK: RAM as Activity Monitor counts it

    static let mb: Int64 = 1024 * 1024

    /// The footprint of each process when the kernel gave one, its resident size otherwise; the tree only.
    @Test func memorySumsFootprintsOfTheTreeAndFallsBackToResident() {
        let snapshot = ProcessMonitor.snapshot(psOutput: ps, footprints: [403: 90 * Self.mb, 407: 400 * Self.mb, 401: 7 * Self.mb])
        // 408 and 409 have no footprint: their resident size counts. 401's footprint is another tree.
        #expect(snapshot.memoryBytes(of: 403) == 90 * Self.mb + 400 * Self.mb + Int64(50_000 + 200_000) * 1024)
        #expect(snapshot.memoryBytes(of: 406) == Int64(130_000) * 1024)
    }

    @Test func footprintIsAskedOfTheKernel() {
        #expect((ProcessMonitor.footprint(of: getpid()) ?? 0) > 0)
        #expect(ProcessMonitor.footprint(of: 99_999_999) == nil)
    }

    /// Measuring asks the kernel about Claude's processes only, never about any other process on the Mac.
    @Test func measuringAsksOnlyAboutClaudeProcesses() throws {
        let asked = PidRecorder()
        let monitor = ProcessMonitor(psOutput: { self.ps + "\n  501 1 3000 /bin/zsh -l\n  502 501 80000 claude --resume\n  503 502 20000 /usr/local/bin/mcp-server\n" },
                                     footprint: { pid in asked.record(pid); return pid == 502 ? 64 * Self.mb : nil })
        _ = try monitor.snapshot()
        #expect(asked.pids.isEmpty)
        let measured = try monitor.snapshot(measuring: true)
        // Every account tree (401 to 409 but vim, 405) and the terminal session's tree (502, 503); not vim, not the shell.
        #expect(asked.pids == [401, 402, 403, 404, 406, 407, 408, 409, 502, 503])
        #expect(measured.footprints == [502: 64 * Self.mb])
    }

    /// Other programs' command lines can hold anything: only Claude's are kept once parsed.
    @Test func argumentsOfOtherProcessesAreNotKept() {
        let snapshot = ProcessMonitor.snapshot(psOutput: ps + "\n  510 1 100 /usr/bin/curl -H secret\n")
        #expect(snapshot.all.first { $0.pid == 405 }?.arguments == "")
        #expect(snapshot.all.first { $0.pid == 510 }?.arguments == "")
        #expect(snapshot.all.first { $0.pid == 510 }?.residentBytes == Int64(102_400))
        #expect(snapshot.all.first { $0.pid == 409 }?.arguments.hasSuffix("/claude") == true)
    }

    // MARK: Claude Code in a terminal

    @Test func isClaudeCodeCases() {
        let yes: [String] = ["claude", "claude -p x", "claude --resume", "/Users/r/.local/bin/claude", "/Users/r/.local/bin/claude --continue",
                   "/opt/homebrew/bin/claude mcp serve",
                   "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js",
                   "node /opt/homebrew/bin/claude", "/usr/local/bin/node /usr/local/bin/claude -p hi", "bun /Users/r/.bun/bin/claude"]
        let no: [String] = ["claude-code-helper", "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
                  "/Applications/Claude.app/Contents/MacOS/Claude", "vim /tmp/claude notes", "less claude", "git -C /Users/r/claude status",
                  "node /Users/r/server.js claude", "/usr/bin/python3 /Users/r/claude.py", ""]
        for line in yes { #expect(ProcessMonitor.isClaudeCode(arguments: line), "\(line)") }
        for line in no { #expect(!ProcessMonitor.isClaudeCode(arguments: line), "\(line)") }
    }

    /// A terminal session is Claude Code with no Claude window and no other session above it; its whole tree counts.
    @Test func terminalSessionsAreClaudeCodeOutsideAnyAccount() {
        let terminal = ps + """

              501 1 3000 /bin/zsh -l
              502 501 80000 claude --resume
              503 502 20000 claude mcp serve
              504 503 10000 /usr/local/bin/some-mcp-server
              505 501 5000 vim /tmp/claude notes
              510 1 3000 -zsh
              511 510 60000 /Users/r/.local/bin/claude
              520 1 90000 node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
            """
        let snapshot = ProcessMonitor.snapshot(psOutput: terminal, footprints: [511: 30 * Self.mb])
        // The Code tab's Claude Code (409) stays with its account; 503 is part of 502's session.
        #expect(snapshot.terminalSessions.map(\.pid) == [502, 511, 520])
        let use = snapshot.terminalUse
        #expect(use.sessions == 3)
        let firstSession: Int64 = (80_000 + 20_000 + 10_000) * 1024
        let npmSession: Int64 = 90_000 * 1024
        #expect(use.bytes == firstSession + 30 * Self.mb + npmSession)
        #expect(ProcessMonitor.snapshot(psOutput: ps).terminalUse == ProcessMonitor.TerminalUse(sessions: 0, bytes: 0))
    }

    @Test func memoryPressureLevelsReadTheKernelValue() {
        #expect(MemoryPressure.Level(sysctlValue: 1) == .normal)
        #expect(MemoryPressure.Level(sysctlValue: 2) == .warning)
        #expect(MemoryPressure.Level(sysctlValue: 4) == .critical)
        #expect(MemoryPressure.current() != nil)
    }

    @Test func realPsRuns() throws {
        _ = try ProcessMonitor().claudeProcesses()
    }
}

final class PidRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: Set<Int32> = []
    func record(_ pid: Int32) { lock.lock(); recorded.insert(pid); lock.unlock() }
    var pids: Set<Int32> { lock.lock(); defer { lock.unlock() }; return recorded }
}
