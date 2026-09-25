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
