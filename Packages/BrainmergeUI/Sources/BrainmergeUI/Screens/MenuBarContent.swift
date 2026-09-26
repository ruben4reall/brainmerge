import AppKit
import SwiftUI
import BrainmergeCore

/// The menu bar icon's menu: the accounts with the sidebar's words, the Mac's RAM, then Brainmerge itself. A native
/// menu (MenuBarExtra's .menu style), so the keyboard, VoiceOver and the system's look come with it. Every text comes
/// from MenuBarMenu.
public struct BrainmergeMenuBar: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        // A message set while the window was closed (an automatic rebuild that failed) waits there: never popped up.
        if let notice = MenuBarMenu.notice(message: model.message, windowOpen: model.windowOpen) {
            Button(notice) { showWindow() }
            Divider()
        }
        // Says why a quit waits, with the window closed.
        if let working = model.working { Text(working) }
        Section("Accounts") {
            ForEach(model.menuEntries) { entry in
                Button { open(entry) } label: {
                    Label { Text(entry.title) } icon: { Image(nsImage: MenuBarIcon.dot(entry.tint)) }
                }
                .disabled(!entry.isEnabled)
                .help(entry.help)
            }
        }
        if let ram = MenuBarMenu.ramLine(model.macMemory) { Text(ram) }
        Divider()
        Button(MenuBarMenu.openTitle) { showWindow() }
        Button(MenuBarMenu.settingsTitle) {
            model.requestedScreen = .settings
            showWindow()
        }
        .keyboardShortcut(",")
        Button(MenuBarMenu.starTitle) { NSWorkspace.shared.open(BrainmergeLinks.repository) }
        Divider()
        // Quits Brainmerge only: the accounts' Claude windows stay open.
        Button(MenuBarMenu.quitTitle) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The sidebar's click; a message it produced shows in the window, brought forward.
    func open(_ entry: MenuBarEntry) {
        Task {
            let before = model.message?.id
            await model.perform(entry.action, on: entry.id)
            if MenuBarMenu.revealsWindow(before: before, after: model.message) { showWindow() }
        }
    }

    /// Brings the one window forward, or opens it again once closed.
    func showWindow() {
        openWindow(id: BrainmergeWindow.main)
        NSApp.activate()
    }
}

/// The icon itself: the creature, eyes open while an account is open or opening.
public struct BrainmergeMenuBarLabel: View {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Image(nsImage: MenuBarIcon.image(awake: MenuBarMenu.iconAwake(accounts: model.accounts, opening: model.opening)))
            .accessibilityLabel(MenuBarMenu.iconLabel(openCount: model.openAccounts.count))
    }
}
