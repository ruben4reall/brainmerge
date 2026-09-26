import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct DiskPlanTests {
    static let mib: Int64 = 1024 * 1024

    static func write(_ size: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: size)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, size) }
        try data.write(to: url)
    }

    /// Where each account's folders really are, the first account first; what lies in another account's folder is
    /// counted there once, and said so.
    @Test func sharedFoldersAreCountedOnce() throws {
        let home = try TempHome(); defer { home.remove() }
        let paths = home.paths
        let ruben = Identity(slug: "ruben", name: "Ruben", isPrimary: true)
        let client = Identity(slug: "client", name: "Client", cliProfilePath: home.url.appending(path: ".claude").path)
        let agency = Identity(slug: "agency", name: "Agency", desktopDataPath: home.url.appending(path: "Library/Application Support/Claude/nested").path)
        let studio = Identity(slug: "studio", name: "Studio", iconMode: .tintedClone)
        let work = Identity(slug: "work", name: "Work")
        var cli = Identity(slug: "cli", name: "Terminal"); cli.surfaces = Surfaces(desktop: false, cli: true)
        // The secondary accounts come first in the list: the first account is planned first anyway.
        let plan = DiskPlan.plan(for: [client, agency, studio, work, ruben, cli], paths: paths)
        let rubenRoots = plan.roots.filter { $0.slug == "ruben" }
        #expect(rubenRoots.map(\.part) == [.claude, .claudeCode])
        // Real paths: the temporary home sits behind the /var link, the walk gets /private/var.
        #expect(rubenRoots.map(\.url.path) == ["/private" + paths.primaryDesktopData.path, "/private" + paths.primaryCLIProfile.path])
        #expect(plan.roots.first?.slug == "ruben")
        #expect(plan.slugs == ["client", "agency", "studio", "work", "ruben", "cli"])

        #expect(plan.countedWith["client"] == [.claudeCode: "ruben"])
        #expect(!plan.roots.contains { $0.slug == "client" && $0.part == .claudeCode })
        #expect(plan.countedWith["agency"] == [.claude: "ruben"])

        let studioApp = try #require(plan.roots.first { $0.slug == "studio" && $0.part == .app })
        #expect(studioApp.privateOnly)
        #expect(studioApp.url.lastPathComponent == "Studio (Claude).app")
        let workApp = try #require(plan.roots.first { $0.slug == "work" && $0.part == .app })
        #expect(!workApp.privateOnly)
        // No app of its own for the first account (it is Claude), none for a Claude Code only account.
        #expect(!plan.roots.contains { ($0.slug == "ruben" || $0.slug == "cli") && $0.part == .app })
        #expect(plan.roots.allSatisfy { !$0.privateOnly || $0.part == .app })
    }

    /// A folder that holds another account's folder leaves it out: nothing is counted twice, whatever the order.
    @Test func aFolderHoldingAnotherLeavesItToItsAccount() throws {
        let home = try TempHome(); defer { home.remove() }
        let outer = home.url.appending(path: "profiles")
        let ruben = Identity(slug: "ruben", name: "Ruben", isPrimary: true, cliProfilePath: outer.appending(path: "ruben").path)
        let client = Identity(slug: "client", name: "Client", cliProfilePath: outer.path)
        try Self.write(1 << 20, to: outer.appending(path: "ruben/projects/a.jsonl"))
        try Self.write(4096, to: outer.appending(path: "client-notes"))
        let plan = DiskPlan.plan(for: [ruben, client], paths: home.paths)
        let disks = DiskPlan.measure(plan) { DiskUsage().size(of: $0.url, skipping: $0.skipping) }
        #expect(disks["ruben"]?.bytes(.claudeCode) ?? 0 >= Self.mib)
        #expect(disks["client"]?.bytes(.claudeCode) ?? Self.mib < Self.mib)
    }

    /// Shared history and shared skills are links to the first account's folders: counted there, said on the other.
    @Test func historyLinkIsNotCountedTwice() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let ruben = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.sharedHistory = true
        let client = try e.manager.add(request)
        try Self.write(1 << 20, to: e.primaryProfile.projectsDir.appending(path: "project/session.jsonl"))
        let plan = DiskPlan.plan(for: [ruben, client], paths: e.home.paths)
        let disks = DiskPlan.measure(plan) { DiskUsage().size(of: $0.url, skipping: $0.skipping) }
        let rubenDisk = try #require(disks["ruben"])
        let clientDisk = try #require(disks["client"])
        #expect(rubenDisk.bytes(.claudeCode) ?? 0 >= Self.mib)
        #expect(clientDisk.bytes(.claudeCode) ?? Self.mib < Self.mib)
        #expect(clientDisk.sharedWith == [.history: "ruben", .skills: "ruben"])
        #expect(rubenDisk.sharedWith.isEmpty)
        #expect(clientDisk.total.complete)
    }

    /// Desktop, Documents, Downloads, iCloud Drive, cloud storage and other disks ask macOS for consent: never walked,
    /// not even through a link, and said "not measured".
    @Test func protectedFoldersAreNotWalked() throws {
        let home = try TempHome(); defer { home.remove() }
        let h = home.url
        for protected in ["Documents/x", "Desktop", "Downloads/a/b", "Library/Mobile Documents/y", "Library/CloudStorage/Dropbox/z"] {
            #expect(DiskPlan.isProtected(h.appending(path: protected), home: h), "\(protected)")
        }
        #expect(DiskPlan.isProtected(URL(fileURLWithPath: "/Volumes/Disk/z"), home: h))
        for fine in ["Library/Application Support/Claude-x", ".claude-x", "DocumentsArchive", "Library/Mobile"] {
            #expect(!DiskPlan.isProtected(h.appending(path: fine), home: h), "\(fine)")
        }

        let adopted = Identity(slug: "work", name: "Work", cliProfilePath: h.appending(path: "Documents/claude-work").path)
        let linked = Identity(slug: "client", name: "Client")
        try FileManager.default.createSymbolicLink(at: h.appending(path: ".claude-client"), withDestinationURL: h.appending(path: "Documents/claude-client"))
        let plan = DiskPlan.plan(for: [adopted, linked], paths: home.paths)
        let asked = PathRecorder()
        let disks = DiskPlan.measure(plan) { root in asked.record(root.url.path); return DiskSize(bytes: 1, complete: true) }
        #expect(disks["work"]?.parts[.claudeCode] == .notMeasured)
        #expect(disks["client"]?.parts[.claudeCode] == .notMeasured)
        #expect(!asked.paths.contains { $0.contains("/Documents") })
    }

    /// A folder that does not exist is left out; the total adds the rest and is complete only if every walk was.
    @Test func totalsAddTheMeasuredPartsOnly() {
        let disk = AccountDisk(slug: "a", parts: [.claude: .measured(DiskSize(bytes: 100, complete: true)),
                                                  .claudeCode: .measured(DiskSize(bytes: 20, complete: false)),
                                                  .app: .countedWith("b")])
        #expect(disk.total == DiskSize(bytes: 120, complete: false))
        let none = AccountDisk(slug: "b", parts: [.claude: .notMeasured])
        #expect(none.total == DiskSize(bytes: 0, complete: true))
        #expect(!none.isMeasured)
        #expect(disk.isMeasured)
    }
}

final class PathRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func record(_ path: String) { lock.lock(); recorded.append(path); lock.unlock() }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
}
