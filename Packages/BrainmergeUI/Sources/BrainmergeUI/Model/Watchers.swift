import Foundation
import BrainmergeCore

public enum UpdatePolicy {
    /// A tinted copy rebuilds itself after a Claude update, if the person opted in and the instance is stopped.
    public static func shouldRebuild(identity: Identity, installedVersion: String, running: Bool, autoRebuild: Bool) -> Bool {
        guard autoRebuild, !running, identity.iconMode == .tintedClone, !identity.isPrimary else { return false }
        return identity.builtForClaudeVersion != installedVersion
    }
}

/// Four clocks: instances (3 s), memory (10 s), projects (60 s), Claude.app (300 s). Which ones run depends on the
/// window and the menu bar icon (see `plan`).
@MainActor
public final class Watchers {
    public enum Clock: CaseIterable, Hashable, Sendable {
        case instances, memory, projects, claude
        public var interval: TimeInterval {
            switch self { case .instances: 3; case .memory: 10; case .projects: 60; case .claude: 300 }
        }
    }

    /// Nothing during the guided setup. The window shows everything, so every clock runs. With the window closed and
    /// the icon shown, the menu's words (instances), new projects and emails (projects; the usage waits for the window) and
    /// the copies after a Claude update (claude) stay current; the memory's history only matters on screen.
    public nonisolated static func plan(windowOpen: Bool, iconShown: Bool, needsOnboarding: Bool) -> Set<Clock> {
        if needsOnboarding { return [] }
        if windowOpen { return Set(Clock.allCases) }
        return iconShown ? [.instances, .projects, .claude] : []
    }

    /// Starts one repeating clock and returns what stops it: a timer in the app, a fake in tests.
    public typealias Schedule = @MainActor (Clock, @escaping @MainActor () -> Void) -> @MainActor () -> Void
    private let schedule: Schedule
    /// What stops each running clock.
    private var stops: [Clock: @MainActor () -> Void] = [:]
    /// What each clock does, from the latest start: a clock kept running calls it on its next tick.
    private var actions: [Clock: @MainActor () -> Void] = [:]

    public init(schedule: @escaping Schedule = Watchers.timer) { self.schedule = schedule }

    /// Runs exactly `clocks`. A clock already running keeps its timer, so the window opening or closing never starts
    /// the minute and five-minute clocks over (each would wait a whole period again, and could never tick).
    public func start(_ clocks: Set<Clock>, running: @escaping @MainActor () -> Void, memory: @escaping @MainActor () -> Void,
                      projects: @escaping @MainActor () -> Void, claude: @escaping @MainActor () -> Void) {
        actions = [.instances: running, .memory: memory, .projects: projects, .claude: claude]
        for clock in Clock.allCases where !clocks.contains(clock) { stops.removeValue(forKey: clock)?() }
        for clock in Clock.allCases where clocks.contains(clock) && stops[clock] == nil {
            stops[clock] = schedule(clock) { [weak self] in self?.actions[clock]?() }
        }
    }

    public func stop() {
        for clock in Clock.allCases { stops.removeValue(forKey: clock)?() }
    }

    /// A repeating timer on the main run loop.
    public static func timer(_ clock: Clock, _ tick: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: clock.interval, repeats: true) { _ in Task { @MainActor in tick() } }
        // Lets macOS batch the wake-ups: they now also run with the window closed.
        timer.tolerance = min(1, clock.interval / 6)
        return { timer.invalidate() }
    }
}

/// Tells when a memory's history moves: a watch on its `.git` folder and on its branches' folder (a commit renames its
/// index into the first and its branch's new ref into the second), a moment after the last change (`debounce`). The
/// memory clock reads the history every 10 s; with this, a save is seen within a fraction of a second and the creature's
/// hop answers it. The clock stays, for what the watch cannot see (a memory folder that was not a repository yet).
@MainActor
public final class MemoryHeadWatch {
    private let debounce: TimeInterval
    private var sources: [DispatchSourceFileSystemObject] = []
    private var root: URL?
    private var pending: DispatchWorkItem?
    private var onChange: (@MainActor () -> Void)?

    public init(debounce: TimeInterval = 0.15) { self.debounce = debounce }

    /// How many folders are watched now (two for a memory with a history).
    public var watchedFolders: Int { sources.count }

    /// Watches `root` (nil: nothing), calling `onChange` on the main actor. Watching the same folder again changes nothing.
    public func watch(_ root: URL?, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard root?.standardizedFileURL != self.root?.standardizedFileURL || (root != nil && sources.isEmpty) else { return }
        stop()
        self.root = root
        guard let root else { return }
        let git = root.appending(path: ".git", directoryHint: .isDirectory)
        for folder in [git, git.appending(path: "refs/heads", directoryHint: .isDirectory)] {
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        for source in sources { source.cancel() }
        sources = []
        root = nil
    }

    /// A burst of changes (a commit touches both folders several times) calls back once, when it is over.
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
