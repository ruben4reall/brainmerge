import SwiftUI
import BrainmergeUI

/// A capture or a demo runs the window alone: no menu bar item is declared, so AppKit writes nothing about one in the
/// preferences a demo shares with the installed app (see `AppLifecycle.declaresMenuBarItem`).
@main
enum BrainmergeMain {
    @MainActor static func main() {
        if AppLifecycle.declaresMenuBarItem(environment: ProcessInfo.processInfo.environment) {
            BrainmergeApp.main()
        } else {
            BrainmergeWindowOnlyApp.main()
        }
    }
}

struct BrainmergeApp: App {
    /// The model lives with the delegate: it outlives the window, and AppKit asks the delegate before quitting.
    @NSApplicationDelegateAdaptor(BrainmergeAppDelegate.self) private var delegate
    var body: some Scene { BrainmergeScenes(model: delegate.model) }
}

struct BrainmergeWindowOnlyApp: App {
    @NSApplicationDelegateAdaptor(BrainmergeAppDelegate.self) private var delegate
    var body: some Scene { BrainmergeWindowScene(model: delegate.model) }
}
