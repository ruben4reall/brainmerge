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

    /// The Accounts menu works with the window closed: it acts on the model, and opens the window only for a sheet.
    func openWindowNow() {
        openWindow(id: BrainmergeWindow.main)
        NSApp.activate()
    }

    func quitAllAsked() {
        let counts = model.quitAllCounts()
        guard counts.windows > 0 else { return }
        let alert = NSAlert()
        alert.messageText = AccountsMenu.quitAllTitle(windows: counts.windows)
        alert.informativeText = AccountsMenu.quitAllDetail(sessions: counts.sessions) ?? ""
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.quitAll() }
    }

    public var body: some Commands {
        CommandMenu("Accounts") {
            ForEach(model.accountsMenuItems) { item in
                // The Log in sheet or a message brings the window (see AppModel.windowRequests).
                let button = Button(item.title) { model.openFromMenu(item.id) }
                .disabled(!item.entry.isEnabled || route == .off)
                if let key = item.shortcut {
                    button.keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option])
                } else {
                    button
                }
            }
            Divider()
            Button(AccountsMenu.addTitle) {
                model.requestedScreen = .accounts
                model.requestedAdd = true
                openWindowNow()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(route == .off)
            Button(AccountsMenu.quitAllTitle) { quitAllAsked() }
                .disabled(model.openAccounts.isEmpty)
        }
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
