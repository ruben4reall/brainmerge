import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct SyncLogTests {
    /// Hooks write at the same moment: every line is kept whole, none written over another.
    @Test func linesWrittenAtOnceAreAllKept() throws {
        let home = try TempHome(); defer { home.remove() }
        let log = SyncLog(paths: home.paths)
        DispatchQueue.concurrentPerform(iterations: 400) { n in log.write("line \(n)") }
        let lines = try String(contentsOf: log.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 400)
        let numbers: Set<String> = Set(lines.compactMap { line -> String? in line.split(separator: " ").last.map(String.init) })
        let expected: Set<String> = Set((0..<400).map { String($0) })
        #expect(numbers == expected)
    }

    /// Past its limit, the log moves to sync.log.1 and starts again: it never grows for good.
    @Test func theLogMovesAsideOnceFull() throws {
        let home = try TempHome(); defer { home.remove() }
        let log = SyncLog(paths: home.paths, limit: 200)
        for n in 0..<20 { log.write("line \(n)") }
        let size = try FileManager.default.attributesOfItem(atPath: log.file.path)[.size] as? Int ?? 0
        #expect(size < 300)
        #expect(FileManager.default.fileExists(atPath: log.file.path + ".1"))
        #expect(try String(contentsOf: log.file, encoding: .utf8).hasSuffix("line 19\n"))
    }
}
