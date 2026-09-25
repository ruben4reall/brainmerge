import SwiftUI

public enum BrainmergeWindow {
    /// The one main window: the menu bar and the app menu bring it forward or open it again.
    public static let main = "main"
}

/// The app's scenes: one main window (no File > New Window, so never two windows on one model) and the menu bar icon.
public struct BrainmergeScenes: Scene {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        // Read here, not only in the binding: the scenes are drawn again when it changes, so the switch in Settings
        // shows or hides the icon at once.
        let shown = model.showsMenuBarIcon
        Window("Brainmerge", id: BrainmergeWindow.main) { RootView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            // The splash and the guide need the window at every launch; a quit with the window closed never reopens
            // Brainmerge windowless.
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { BrainmergeCommands(model: model) }
        MenuBarExtra(isInserted: Binding(get: { shown }, set: { inserted in
            // The person dragged the icon out of the menu bar: saved as off. Only from a visible icon, since SwiftUI can
            // echo false after the app hid it (splash, guide, capture), which must not turn the setting off for good.
            if !inserted, model.showsMenuBarIcon { model.setMenuBarIcon(false) }
        })) {
            BrainmergeMenuBar(model: model)
        } label: {
            BrainmergeMenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
