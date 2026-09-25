import AppKit
import SwiftUI

/// The screen the focused window shows, for the menu bar to switch it.
struct BrainmergeSectionKey: FocusedValueKey { typealias Value = Binding<RootView.Section> }

extension FocusedValues {
    var brainmergeSection: Binding<RootView.Section>? {
        get { self[BrainmergeSectionKey.self] }
        set { self[BrainmergeSectionKey.self] = newValue }
    }
}

/// The menu bar: the four screens in the View menu with Cmd-1 to Cmd-4, and Settings… with Cmd-comma, where people and
/// VoiceOver find them. They act on the window, open it on that screen when it is closed (Brainmerge kept in the menu
/// bar), and are off while it shows the splash or the guided setup.
public struct BrainmergeCommands: Commands {
    @FocusedBinding(\.brainmergeSection) private var section: RootView.Section?
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    static var screens: [RootView.Section] { RootView.Section.allCases }
    static let settingsKey: Character = ","

    enum Route: Equatable { case switchScreen, openWindow, off }

    /// No focused window with its screens: either the window is closed (or not in front), and the item opens it, or it
    /// shows the splash or the guide, and the item waits.
    static func route(focused: Bool, setupDone: Bool) -> Route {
        if focused { return .switchScreen }
        return setupDone ? .openWindow : .off
    }

    var route: Route { Self.route(focused: section != nil, setupDone: model.setupDone) }

    func show(_ screen: RootView.Section) {
        switch route {
        case .switchScreen: section = screen
        case .openWindow:
            model.requestedScreen = screen
            openWindow(id: BrainmergeWindow.main)
            NSApp.activate()
        case .off: break
        }
    }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.settings) }
                .keyboardShortcut(KeyEquivalent(Self.settingsKey), modifiers: .command)
                .disabled(route == .off)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Self.screens) { screen in
                Button(screen.title) { show(screen) }
                    .keyboardShortcut(KeyEquivalent(screen.digit), modifiers: .command)
                    .disabled(route == .off)
            }
            Divider()
        }
    }
}
