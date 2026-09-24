import Foundation
import BrainmergeCore

public enum UpdatePolicy {
    /// A tinted copy rebuilds itself after a Claude update, if the person opted in and the instance is stopped.
    public static func shouldRebuild(identity: Identity, installedVersion: String, running: Bool, autoRebuild: Bool) -> Bool {
        guard autoRebuild, !running, identity.iconMode == .tintedClone, !identity.isPrimary else { return false }
        return identity.builtForClaudeVersion != installedVersion
    }
}

/// Four clocks: instances (3 s), memory (10 s), projects (60 s), Claude.app (300 s).
@MainActor
public final class Watchers {
    private var timers: [Timer] = []

    public init() {}

    public func start(running: @escaping @MainActor () -> Void, memory: @escaping @MainActor () -> Void,
                      projects: @escaping @MainActor () -> Void, claude: @escaping @MainActor () -> Void) {
        stop()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { @MainActor in running() } },
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in Task { @MainActor in memory() } },
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in projects() } },
            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in Task { @MainActor in claude() } },
        ]
    }

    public func stop() { timers.forEach { $0.invalidate() }; timers = [] }
}
