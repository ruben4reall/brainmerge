import AppKit

/// When the menu bar icon shows, and what closing the window or quitting does. Pure, so the app delegate and the
/// scenes only ask; the rules are tested here.
public enum AppLifecycle {
    /// A capture, a README picture or a demo: the splash keys, or a demo home (BRAINMERGE_HOME, set only by tests and
    /// scripts). An icon there would end up in pictures and sit next to the installed app's own.
    public static func isCaptureOrDemo(environment: [String: String]) -> Bool {
        AppModel.skipsSplash(environment: environment) || environment["BRAINMERGE_HOME"].map { !$0.isEmpty } == true
    }

    /// Only once the window shows its screens and the guided setup is closed: before that, closing the window must quit,
    /// and the menu would offer accounts that do not exist yet.
    public static func showsMenuBarIcon(setting: Bool, phase: LaunchPhase, setupDone: Bool, environment: [String: String]) -> Bool {
        setting && phase == .ready && setupDone && !isCaptureOrDemo(environment: environment)
    }

    /// With the icon, Brainmerge stays in the menu bar once its window is closed; without it, nothing would be left to
    /// click but the Dock, so it quits.
    public static func quitsWhenLastWindowCloses(iconShown: Bool) -> Bool { !iconShown }

    /// The icon dragged out of the menu bar with the window closed would leave Brainmerge running with nothing to click
    /// but the Dock: the window opens again.
    public static func reopensWindow(afterIconRemovedWith windowOpen: Bool) -> Bool { !windowOpen }

    /// Work on an account's app (a copy rebuilt, renamed, removed) is never cut in half by a quit.
    public static func terminateReply(workInProgress: Bool) -> NSApplication.TerminateReply {
        workInProgress ? .terminateLater : .terminateNow
    }
}
