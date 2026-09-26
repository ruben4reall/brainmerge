import Darwin
import Foundation

/// What a Claude update means for the windows already open, decided from snapshots only: nothing here reads a disk,
/// quits or opens anything by itself. The app feeds it each reload (`observe`) and says what it returns.
public struct UpdateWatch: Equatable, Sendable {
    /// A new Claude version, as first seen: when (in mach absolute time and on the wall clock), and when its bundle changed.
    public struct Change: Equatable, Sendable {
        public let version: String
        public let observedAbstime: UInt64
        public let observedAt: Date
        public let bundleModified: Date
        public init(version: String, observedAbstime: UInt64, observedAt: Date, bundleModified: Date) {
            self.version = version; self.observedAbstime = observedAbstime; self.observedAt = observedAt; self.bundleModified = bundleModified
        }
    }

    /// One account's window as a reload saw it.
    public struct Window: Equatable, Sendable {
        public let slug: String
        public let isPrimary: Bool
        public let running: Bool
        /// When its main process started, in mach absolute time (nil when unknown).
        public let startAbstime: UInt64?
        /// A tinted copy runs its own copy of Claude, not the bundle that was updated: a restart would bring back the
        /// same copy, so it is never called stale. Its own Update rebuilds it.
        public let isCopy: Bool
        public init(slug: String, isPrimary: Bool, running: Bool, startAbstime: UInt64?, isCopy: Bool = false) {
            self.slug = slug; self.isPrimary = isPrimary; self.running = running; self.startAbstime = startAbstime; self.isCopy = isCopy
        }
    }

    /// What the app says, each once.
    public enum Event: Equatable, Sendable {
        /// Claude came back on the first account's folders after `instead`'s window closed for an update.
        case bareRelaunch(instead: String)
        /// `target` was asked to open, and Claude came up on the first account's folders instead.
        case openedElsewhere(target: String)
    }

    /// An account's window that closed, and whether the first account was running just before (the last reload
    /// that still saw the window): then a first account seen coming back is its own restart, not a bare relaunch.
    struct Exit: Equatable, Sendable { let slug: String; let at: Date; let primaryWasRunning: Bool }

    /// The last version change seen, and the windows that started before it.
    public private(set) var change: Change?
    public private(set) var stale: Set<String> = []
    private var seenVersion: String?
    private var runningBefore: Set<String>?
    private var lastSecondaryExit: Exit?
    private var primaryAppearedAt: Date?
    /// Accounts the person asked to open, and when.
    private var openRequests: [String: Date] = [:]

    /// How long a version change can explain a bare Claude: Claude replaces itself, then comes back within a minute.
    static let recentChange: TimeInterval = 300

    public init() {}

    /// The person asked this account to open (through Brainmerge): it is theirs, and a bare Claude instead is said.
    public mutating func requestedOpen(_ slug: String, at date: Date) { openRequests[slug] = date }

    /// One reload: Claude's version now, every account's window, the clocks. `bundleModified` is read only when the
    /// version changed.
    public mutating func observe(version: String, windows: [Window], now: Date, abstime: UInt64, ticksPerSecond: Double,
                                 bundleModified: () -> Date?) -> [Event] {
        if let seen = seenVersion, seen != version {
            change = Change(version: version, observedAbstime: abstime, observedAt: now, bundleModified: bundleModified() ?? now)
        }
        seenVersion = version
        stale = Set(windows.filter { $0.running && !$0.isCopy && Self.isStale(startAbstime: $0.startAbstime, change: change, ticksPerSecond: ticksPerSecond) }.map(\.slug))

        var events: [Event] = []
        let running = Set(windows.filter(\.running).map(\.slug))
        let primary = windows.first(where: \.isPrimary)?.slug
        if let before = runningBefore, let primary {
            let secondaries = Set(windows.filter { !$0.isPrimary }.map(\.slug))
            if let exited = before.subtracting(running).intersection(secondaries).sorted().first {
                lastSecondaryExit = Exit(slug: exited, at: now, primaryWasRunning: before.contains(primary))
            }
            if running.contains(primary), !before.contains(primary) {
                primaryAppearedAt = now
                let versionChanged = change.map { now.timeIntervalSince($0.observedAt) <= Self.recentChange } ?? false
                if let exit = lastSecondaryExit,
                   Self.isBareRelaunch(now: now, lastSecondaryExit: exit.at, primaryWasRunning: exit.primaryWasRunning, versionChanged: versionChanged,
                                       primaryOpenedByPerson: openRequests[primary] != nil) {
                    events.append(.bareRelaunch(instead: exit.slug))
                }
                // The exit is used up by the first appearance, said or not: a first account opened on purpose, then
                // quit and opened again within the minute, never came back instead of that window.
                lastSecondaryExit = nil
            }
            if !running.contains(primary) { primaryAppearedAt = nil }
        }
        runningBefore = running

        for (slug, since) in openRequests.sorted(by: { $0.key < $1.key }) {
            if running.contains(slug) || now.timeIntervalSince(since) > 60 || !windows.contains(where: { $0.slug == slug }) {
                openRequests[slug] = nil; continue
            }
            guard slug != primary else { continue }
            let bare = primaryAppearedAt.map { $0 >= since } ?? false
            if Self.openedElsewhere(since: since, now: now, targetRunning: false, bareAppeared: bare) {
                openRequests[slug] = nil
                events.append(.openedElsewhere(target: slug))
            }
        }
        return events
    }

    /// Mach ticks per second on this Mac.
    public static var ticksPerSecond: Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return 1_000_000_000 * Double(info.denom) / Double(max(info.numer, 1))
    }

    /// The change in mach absolute time, conservatively: abstime stops while the Mac sleeps and the wall clock does
    /// not, so going back by the wall time lands at or before the real change. A Mac that slept only makes fewer
    /// windows look stale, never more.
    public static func cutoff(of change: Change, ticksPerSecond: Double) -> UInt64 {
        let seconds = max(0, change.observedAt.timeIntervalSince(change.bundleModified))
        let ticks = seconds * ticksPerSecond
        guard ticks < Double(change.observedAbstime) else { return 0 }
        return change.observedAbstime - UInt64(ticks)
    }

    /// A window that started before the change still runs the previous Claude.
    public static func isStale(startAbstime: UInt64?, change: Change?, ticksPerSecond: Double) -> Bool {
        guard let startAbstime, let change else { return false }
        return startAbstime < cutoff(of: change, ticksPerSecond: ticksPerSecond)
    }

    /// Claude's own "Restart to update", clicked in another account's window, can come back with no arguments, so on
    /// the first account's folders. Said only when all hold: an account's window closed within the last 60 s, the first
    /// account was not running when it closed, Claude's version changed, and the person did not open the first account.
    public static func isBareRelaunch(now: Date, lastSecondaryExit: Date?, primaryWasRunning: Bool, versionChanged: Bool,
                                      primaryOpenedByPerson: Bool) -> Bool {
        guard let exit = lastSecondaryExit, now.timeIntervalSince(exit) <= 60 else { return false }
        return !primaryWasRunning && versionChanged && !primaryOpenedByPerson
    }

    /// An account asked to open is still not running after 10 s, while a bare Claude came up meanwhile.
    public static func openedElsewhere(since: Date, now: Date, targetRunning: Bool, bareAppeared: Bool) -> Bool {
        now.timeIntervalSince(since) >= 10 && !targetRunning && bareAppeared
    }

    /// Quit, wait for the exit (10 s at most), then open: never opened while the old one runs, never twice.
    /// False when the window did not exit in time, and then nothing is opened.
    public static func restart(quit: @Sendable () async -> Void, isRunning: @Sendable () async -> Bool,
                               launch: @Sendable () async -> Void, pause: @Sendable (Duration) async -> Void,
                               timeout: Duration = .seconds(10)) async -> Bool {
        await quit()
        let step = Duration.milliseconds(250)
        var waited = Duration.zero
        while await isRunning() {
            guard waited < timeout else { return false }
            await pause(step)
            waited += step
        }
        await launch()
        return true
    }
}
