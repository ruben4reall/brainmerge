import AppKit
import SwiftUI

public enum BrainmergeWindow {
    /// The one main window: the menu bar and the app menu bring it forward or open it again.
    public static let main = "main"
}

/// The app's scenes: one main window (no File > New Window, so never two windows on one model) and the menu bar icon.
public struct BrainmergeScenes: Scene {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        // Read here, not only in the binding: the scenes are drawn again when it changes, so the switch in Settings
        // shows or hides the icon at once.
        let shown = model.showsMenuBarIcon
        BrainmergeWindowScene(model: model)
        MenuBarExtra(isInserted: Binding(get: { shown }, set: { inserted in
            // The person dragged the icon out of the menu bar: saved as off, and the window opens again if it was closed
            // (see AppModel.menuBarIconRemoved).
            if !inserted, model.menuBarIconRemoved() {
                openWindow(id: BrainmergeWindow.main)
                NSApp.activate()
            }
        })) {
            BrainmergeMenuBar(model: model)
        } label: {
            BrainmergeMenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The main window alone. A capture or a demo runs only this one (see `AppLifecycle.declaresMenuBarItem`): with no menu
/// bar item declared, AppKit records nothing about one in the preferences it shares with the installed app.
public struct BrainmergeWindowScene: Scene {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        Window("Brainmerge", id: BrainmergeWindow.main) { RootView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            // The splash and the guide need the window at every launch; a quit with the window closed never reopens
            // Brainmerge windowless.
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { BrainmergeCommands(model: model) }
            // A link or the Accounts menu needs the window (a screen, the Log in sheet, a message): opened again when
            // closed, brought forward otherwise.
            .onChange(of: model.windowRequests) {
                openWindow(id: BrainmergeWindow.main)
                NSApp.activate()
            }
    }
}
