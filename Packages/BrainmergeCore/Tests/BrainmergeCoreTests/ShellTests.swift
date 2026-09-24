import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ShellTests {
    @Test func capturesStdoutStderrAndStatus() throws {
        let r = try Shell().run("/bin/sh", ["-c", "echo out; echo err 1>&2; exit 3"])
        #expect(r.status == 3)
        #expect(r.stdout == "out\n")
        #expect(r.stderr == "err\n")
    }
    @Test func checkThrowsOnFailure() {
        #expect(throws: BrainmergeError.self) { try Shell().check("/bin/sh", ["-c", "exit 1"]) }
    }
    @Test func environmentAndWorkingDirectory() throws {
        let home = try TempHome(); defer { home.remove() }
        let out = try Shell().check("/bin/sh", ["-c", "echo $BRAINMERGE_TEST; pwd"],
                                    cwd: home.url, environment: ["BRAINMERGE_TEST": "yes"])
        #expect(out.hasPrefix("yes\n"))
        #expect(out.contains(home.url.lastPathComponent))
    }
}
