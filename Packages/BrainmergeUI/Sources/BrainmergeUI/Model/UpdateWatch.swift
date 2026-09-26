import Darwin
import Foundation

/// What a Claude update means for the windows already open, decided from snapshots only: nothing here reads a disk,
/// quits or opens anything by itself.
public enum UpdateWatch {
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
    /// account was not running before, Claude's version changed, and the person did not open the first account.
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
