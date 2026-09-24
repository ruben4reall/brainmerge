import Foundation
import BrainmergeCore

/// A temporary, disposable HOME, for tests.
public struct TempHome {
    public let url: URL
    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "brainmerge-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    public var paths: Paths { Paths(home: url) }
    public func remove() { try? FileManager.default.removeItem(at: url) }
}
