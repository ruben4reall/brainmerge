import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct UsageGroupingTests {
    /// Two accounts on one shared history read the same transcripts: one group, counted once, on the Usage screen and in
    /// `brainmerge usage` alike.
    @Test func aSharedHistoryIsOneGroup() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        try FileManager.default.createDirectory(at: e.primaryProfile.projectsDir, withIntermediateDirectories: true)
        var shared = IdentityManager.AddRequest(name: "Studio")
        shared.sharedHistory = true
        _ = try e.manager.add(shared)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let groups = UsageGrouping.groups(of: try e.store.load().identities, paths: e.home.paths)
        #expect(groups.map { $0.map(\.name) } == [["Perso", "Studio"], ["Work"]])
    }
}
