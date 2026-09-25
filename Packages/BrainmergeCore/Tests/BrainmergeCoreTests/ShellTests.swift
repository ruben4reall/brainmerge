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

/// Claude Code is started with exactly the variables Brainmerge chose: Brainmerge's own environment, which can hold
/// keys, never reaches it. Only system programs run here, never Claude Code.
@Suite struct IsolatedShellTests {
    @Test func theProgramSeesOnlyTheGivenVariables() throws {
        let home = try TempHome(); defer { home.remove() }
        let r = try Shell().runIsolated("/usr/bin/env", [], cwd: home.url,
                                        environment: ["HOME": "/nowhere", "PATH": "/usr/bin:/bin"], timeout: 10)
        #expect(r.status == 0)
        #expect(Set(r.stdout.split(separator: "\n").map(String.init)) == ["HOME=/nowhere", "PATH=/usr/bin:/bin"])
    }

    @Test func runsInTheGivenFolderAndCapturesBothStreams() throws {
        let home = try TempHome(); defer { home.remove() }
        let r = try Shell().runIsolated("/bin/sh", ["-c", "pwd; echo err 1>&2; exit 4"], cwd: home.url, environment: [:], timeout: 10)
        #expect(r.status == 4)
        #expect(r.stdout.hasSuffix(home.url.lastPathComponent + "\n"))
        #expect(r.stderr == "err\n")
    }

    /// Both streams are read while the program runs: a program that fills both pipes finishes instead of waiting forever.
    @Test(.timeLimit(.minutes(1))) func largeOutputOnBothStreamsDoesNotBlock() throws {
        let script = "head -c 200000 /dev/zero | tr '\\0' a; head -c 150000 /dev/zero | tr '\\0' b 1>&2"
        let r = try Shell().runIsolated("/bin/sh", ["-c", script], cwd: nil, environment: ["PATH": "/usr/bin:/bin"], timeout: 30)
        #expect(r.status == 0)
        #expect(r.stdout.count == 200_000 && r.stdout.allSatisfy { $0 == "a" })
        #expect(r.stderr.count == 150_000)
    }

    @Test func aProgramThatCannotStartThrows() {
        #expect(throws: (any Error).self) {
            try Shell().runIsolated("/nonexistent/program", [], cwd: nil, environment: [:], timeout: 5)
        }
    }
}
