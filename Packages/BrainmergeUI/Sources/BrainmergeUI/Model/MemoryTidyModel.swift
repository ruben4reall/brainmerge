import Foundation
import Observation
import BrainmergeCore

/// The Memory screen's Tidy tab: what MemoryHealth found in the selected memory, read off the main thread. Only reads;
/// the buttons (see the AppModel extension below) each change one thing on a click.
@MainActor @Observable
public final class MemoryTidyModel {
    /// Nil until the first read of the memory shown.
    public private(set) var report: MemoryHealth.Report?
    /// The memory the report is about.
    public private(set) var root: URL?
    /// The tab's "Tidy (4)".
    public var count: Int { report?.count ?? 0 }
    /// Bumped when the memory changes: a read started for the previous one is thrown away when it ends.
    @ObservationIgnored private var generation = 0

    public init() {}

    func refresh(brain: Brain?, accountSlugs: Set<String>, held: Set<String>, git: GitAvailability) async {
        guard let brain else { generation += 1; report = nil; root = nil; return }
        if brain.root != root { generation += 1; report = nil; root = brain.root }
        let mine = generation
        let found = await Task.detached(priority: .utility) {
            MemoryHealth.analyze(MemoryHealth.read(brain: brain, git: BrainGit(brain: brain, availability: git), accountSlugs: accountSlugs, held: held))
        }.value
        guard mine == generation else { return }
        if found != report { report = found }
    }
}

extension AppModel {
    /// Reads the selected memory again for the Tidy tab. The accounts' slugs find the copies they left; the notes the
    /// secret guard held back are left to their own banner.
    public func refreshTidy() async {
        await memoryTidy.refresh(brain: selectedBrain, accountSlugs: Set(accounts.map(\.identity.slug)), held: Set(heldNotes.map(\.path)), git: git)
    }

    /// The tidy buttons' helper on the selected memory, nil when there is none.
    var tidy: MemoryTidy? {
        guard let brain = selectedBrain else { return nil }
        return MemoryTidy(brain: brain, git: BrainGit(brain: brain, availability: git))
    }

    /// What File under would move, for its preview: nothing changes yet.
    public func planFiling(_ folder: String, under project: String) async -> MemoryTidy.Plan? {
        guard let tidy else { return nil }
        let outcome = await Task.detached(priority: .userInitiated) { Result { try tidy.plan(filing: folder, under: project) } }.value
        switch outcome {
        case .success(let plan): return plan
        case .failure(let error): present(error); return nil
        }
    }

    /// "Move": the notes and their index lines, in one commit as You.
    public func file(_ plan: MemoryTidy.Plan) async {
        let label = plan.notes.count == 1 ? "Filing a note under \(plan.to)…" : "Filing \(plan.notes.count) notes under \(plan.to)…"
        await tidyAction(label) { try $0.file(plan) }
    }

    /// "Keep this one": the other copy goes to the project's `_archive/`.
    public func keep(_ kept: String, over other: String) async {
        await tidyAction("Keeping one copy…") { try $0.keep(kept, over: other) }
    }

    /// "Hide": the empty quick session folders leave the tab; the folders stay.
    public func hideEmptyFolders(_ item: MemoryHealth.Item) async {
        let folders = item.files.map { ($0 as NSString).lastPathComponent }
        await tidyAction("Hiding the empty folders…") { try $0.hide(folders) }
    }

    /// Both copies of a note for Compare, read off the main thread: each file's name and text (64 KB at most), only from
    /// inside the memory.
    public func readCopies(_ item: MemoryHealth.Item) async -> [(name: String, text: String)] {
        guard let root = selectedBrain?.root else { return [] }
        let files = item.files
        return await Task.detached(priority: .userInitiated) { () -> [(name: String, text: String)] in
            let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            return files.compactMap { path in
                let url = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
                guard url.path.hasPrefix(base), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                defer { try? handle.close() }
                return (url.lastPathComponent, String(decoding: (try? handle.read(upToCount: 64 * 1024)) ?? Data(), as: UTF8.self))
            }
        }.value
    }

    /// Runs one tidy button on the core queue with its waiting sentence (a refusal says why), then reads the timeline and
    /// the tab again.
    private func tidyAction(_ label: String, _ work: @escaping @Sendable (MemoryTidy) throws -> Void) async {
        guard let tidy else { return }
        _ = await perform(label) { try work(tidy) }
        refreshMemory()
        await refreshTidy()
    }
}
