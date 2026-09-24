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
        #expect(snapshot.residentBytes(of: 403) == Int64(120_000 + 300_000 + 50_000 + 200_000) * 1024)
        #expect(snapshot.residentBytes(of: 401) == Int64(100_000 + 700_000) * 1024)
        #expect(snapshot.residentBytes(of: 406) == Int64(130_000) * 1024)
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
