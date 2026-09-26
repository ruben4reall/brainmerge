import Foundation
import Testing
@testable import BrainmergeCore

@Suite struct ProcessStartTests {
    let ps = """
      401 1 100000 /Applications/Claude.app/Contents/MacOS/Claude
      403 1 120000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/r/Library/Application Support/Claude-work
      409 403 200000 /Users/r/Library/Application Support/Claude-work/claude-code/2.1.280/claude
      410 409 1000 /bin/zsh -c ls
    """

    @Test func mainsCarryTheirStartFromTheSameKernelCall() throws {
        let monitor = ProcessMonitor(psOutput: { ps }, startTime: { $0 == 401 ? 1_000 : ($0 == 403 ? 2_000 : nil) })
        let snapshot = try monitor.snapshot()
        #expect(snapshot.mains.map(\.startAbstime) == [1_000, 2_000])
    }

    @Test func aClaudeCodeSessionUnderAWindowIsSeen() {
        let snapshot = ProcessMonitor.snapshot(psOutput: ps)
        #expect(snapshot.hasClaudeCode(under: 403))
        #expect(!snapshot.hasClaudeCode(under: 401))
    }
}
