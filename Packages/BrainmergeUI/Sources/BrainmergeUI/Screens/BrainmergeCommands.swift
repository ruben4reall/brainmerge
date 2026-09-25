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
/// VoiceOver find them. They act on the focused window, and are off while it shows the splash or the guided setup.
public struct BrainmergeCommands: Commands {
    @FocusedBinding(\.brainmergeSection) private var section: RootView.Section?

    public init() {}

    static var screens: [RootView.Section] { RootView.Section.allCases }
    static let settingsKey: Character = ","

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { section = .settings }
                .keyboardShortcut(KeyEquivalent(Self.settingsKey), modifiers: .command)
                .disabled(section == nil)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Self.screens) { screen in
                Button(screen.title) { section = screen }
                    .keyboardShortcut(KeyEquivalent(screen.digit), modifiers: .command)
                    .disabled(section == nil)
            }
            Divider()
        }
    }
}
