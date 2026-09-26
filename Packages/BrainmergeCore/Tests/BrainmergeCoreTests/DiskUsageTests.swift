import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct DiskUsageTests {
    static let mib: Int64 = 1024 * 1024

    /// Bytes that do not compress or deduplicate, so the file system really allocates them.
    static func write(_ size: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: size)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, size) }
        try data.write(to: url)
    }

    /// Allocated blocks, a hard link once, a link never followed, a missing folder is nothing at all.
    @Test func sizesAddUpAllocatedBlocksWithoutFollowingLinks() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "data")
        try Self.write(4096, to: root.appending(path: "small"))
        try Self.write(1 << 20, to: root.appending(path: "sub/big"))
        try FileManager.default.linkItem(at: root.appending(path: "sub/big"), to: root.appending(path: "big-again"))
        try Self.write(10 << 20, to: home.url.appending(path: "outside/huge"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: home.url.appending(path: "outside"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "file-link"), withDestinationURL: home.url.appending(path: "outside/huge"))

        let size = try #require(DiskUsage().size(of: root))
        #expect(size.bytes >= 4096 + Self.mib)
        #expect(size.bytes < 2 * Self.mib, "the hard link counts once and links are not followed: \(size.bytes)")
        #expect(size.complete)
        #expect(DiskUsage().size(of: home.url.appending(path: "missing")) == nil)
    }

    @Test func aLimitOrCancellationStopsTheWalkAndSaysSo() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "data")
        for index in 0..<5 { try Self.write(4096, to: root.appending(path: "f\(index)")) }
        let full = try #require(DiskUsage().size(of: root))
        #expect(full.complete)
        let limited = try #require(DiskUsage(entryLimit: 2).size(of: root))
        #expect(!limited.complete)
        #expect(limited.bytes < full.bytes)
        #expect(DiskUsage().size(of: root, isCancelled: { true })?.complete == false)
        #expect(DiskUsage(timeLimit: .zero).size(of: root)?.complete == false)
    }

    /// Another account's folder found inside this one is left to that account.
    @Test func aSkippedFolderIsNotCounted() throws {
        let home = try TempHome(); defer { home.remove() }
        let root = home.url.appending(path: "data")
        try Self.write(4096, to: root.appending(path: "mine"))
        try Self.write(1 << 20, to: root.appending(path: "other/theirs"))
        let size = try #require(DiskUsage().size(of: root, skipping: [root.appending(path: "other")]))
        #expect(size.bytes >= 4096 && size.bytes < Self.mib)
        #expect(size.complete)
    }

    /// A tinted copy is an APFS clone of Claude: only the blocks it does not share are its own.
    @Test func aCloneCountsOnlyWhatItDoesNotShare() throws {
        let home = try TempHome(); defer { home.remove() }
        guard (try? home.url.resourceValues(forKeys: [.volumeSupportsFileCloningKey]))?.volumeSupportsFileCloning == true else { return }
        let alone = home.url.appending(path: "alone/file")
        try Self.write(8 << 20, to: alone)
        // A file that shares nothing is all its own: the private size is read right, not zero.
        let own = try #require(DiskUsage().size(of: alone.deletingLastPathComponent(), privateOnly: true))
        #expect(own.bytes >= 8 * Self.mib)
        #expect(own.sharedBytes == 0)

        let pair = home.url.appending(path: "pair")
        try Self.write(8 << 20, to: pair.appending(path: "original"))
        try FileManager.default.copyItem(at: pair.appending(path: "original"), to: pair.appending(path: "clone"))
        let allocated = try #require(DiskUsage().size(of: pair))
        #expect(allocated.bytes >= 16 * Self.mib)
        let privately = try #require(DiskUsage().size(of: pair, privateOnly: true))
        #expect(privately.bytes < Self.mib)
        #expect(privately.sharedBytes >= 16 * Self.mib)
    }
}
