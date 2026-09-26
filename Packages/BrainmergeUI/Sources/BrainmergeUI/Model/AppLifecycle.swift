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
    /// click but the Dock, so it quits. A registered quick opener shortcut is something to press: it stays for it too.
    public static func quitsWhenLastWindowCloses(iconShown: Bool, openerActive: Bool) -> Bool { !iconShown && !openerActive }

    /// The icon dragged out of the menu bar with the window closed would leave Brainmerge running with nothing to click
    /// but the Dock: the window opens again.
    public static func reopensWindow(afterIconRemovedWith windowOpen: Bool) -> Bool { !windowOpen }

    /// AppKit restores no window: the one window opens at every launch (`defaultLaunchBehavior(.presented)`). A state
    /// saved by 0.5, whose window group SwiftUI no longer makes, would be restored to no window at all, and the window
    /// would then never open.
    public static let restoresWindows = false

    /// Forgets the window state AppKit saved for this app (an older version's), before AppKit reads it at launch. Only
    /// this app's own folder; nothing without a bundle identifier.
    public static func forgetSavedWindows(bundleID: String?, home: URL) {
        guard let bundleID, !bundleID.isEmpty else { return }
        let folder = home.appending(path: "Library/Saved Application State/\(bundleID).savedState", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Work on an account's app (a copy rebuilt, renamed, removed) is never cut in half by a quit.
    public static func terminateReply(workInProgress: Bool) -> NSApplication.TerminateReply {
        workInProgress ? .terminateLater : .terminateNow
    }
}
