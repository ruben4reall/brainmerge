import AppKit

/// Owns the model for the whole process (the window comes and goes, the menu bar icon stays) and answers AppKit's
/// questions about closing and quitting with AppLifecycle's rules.
@MainActor
public final class BrainmergeAppDelegate: NSObject, NSApplicationDelegate {
    public let model = AppModel.live()
    /// The longest a quit waits for work on an account's app: a copy rebuild is a clone and a signature, seconds.
    static let quitWait: Duration = .seconds(120)
    private var quitting = false
    private var menuObserver: NSObjectProtocol?

    /// Before AppKit restores windows: an older version's saved window would leave the app with none (see AppLifecycle).
    public func applicationWillFinishLaunching(_ notification: Notification) {
        AppLifecycle.forgetSavedWindows(bundleID: Bundle.main.bundleIdentifier, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    public func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        AppLifecycle.restoresWindows
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // With no window on screen, macOS may slow the clocks down (App Nap), so the menu reads the accounts again as it
        // opens. Only while Brainmerge is not the active app: the icon's menu is then the only one that can open.
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !NSApp.isActive, self.model.launchPhase == .ready else { return }
                self.model.reload()
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLifecycle.quitsWhenLastWindowCloses(iconShown: model.showsMenuBarIcon)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = AppLifecycle.terminateReply(workInProgress: model.working != nil)
        guard reply == .terminateLater, !quitting else { return reply }
        // One wait, one answer, even if the person asks to quit again meanwhile.
        quitting = true
        Task {
            _ = await model.waitForWork(limit: Self.quitWait)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return reply
    }
}
