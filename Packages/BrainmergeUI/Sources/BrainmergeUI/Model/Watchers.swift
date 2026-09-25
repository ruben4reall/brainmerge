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
    /// the icon shown, the menu's words (instances), new projects and emails (projects) and the copies after a Claude
    /// update (claude) stay current; the memory's history only matters on screen.
    public nonisolated static func plan(windowOpen: Bool, iconShown: Bool, needsOnboarding: Bool) -> Set<Clock> {
        if needsOnboarding { return [] }
        if windowOpen { return Set(Clock.allCases) }
        return iconShown ? [.instances, .projects, .claude] : []
    }

    private var timers: [Timer] = []

    public init() {}

    public func start(_ clocks: Set<Clock>, running: @escaping @MainActor () -> Void, memory: @escaping @MainActor () -> Void,
                      projects: @escaping @MainActor () -> Void, claude: @escaping @MainActor () -> Void) {
        stop()
        let actions: [Clock: @MainActor () -> Void] = [.instances: running, .memory: memory, .projects: projects, .claude: claude]
        timers = Clock.allCases.filter(clocks.contains).compactMap { clock in
            guard let action = actions[clock] else { return nil }
            let timer = Timer.scheduledTimer(withTimeInterval: clock.interval, repeats: true) { _ in Task { @MainActor in action() } }
            // Lets macOS batch the wake-ups: they now also run with the window closed.
            timer.tolerance = min(1, clock.interval / 6)
            return timer
        }
    }

    public func stop() { timers.forEach { $0.invalidate() }; timers = [] }
}
