import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct MenuBarMenuTests {
    func account(_ name: String, primary: Bool = false, desktop: Bool = true, running: Bool = false, session: Bool = true,
                 tint: Tint = .blue) -> Account {
        let identity = Identity(slug: name.lowercased(), name: name, tint: tint, isPrimary: primary, surfaces: Surfaces(desktop: desktop))
        return Account(identity: identity, isRunning: running, hasSession: session)
    }

    var sidebar: [Account] {
        [account("Ruben", primary: true, running: true, tint: .orange), account("Work"), account("Code", desktop: false, session: false),
         account("Client", tint: .green), account("Perso", tint: .purple)]
    }

    /// Only macOS can show an icon it hid: Settings says so, and its button opens System Settings at Menu Bar.
    @Test func hiddenIconNoteNamesSystemSettings() {
        #expect(MenuBarMenu.hiddenByMacOSNote == "macOS hides Brainmerge's icon. Turn it on in System Settings, Menu Bar, under Allow in the Menu Bar.")
        #expect(MenuBarMenu.openMenuBarSettingsTitle == "Open Menu Bar Settings…")
        #expect(MenuBarMenu.menuBarSettings.scheme == "x-apple.systempreferences")
        #expect(MenuBarMenu.menuBarSettings.absoluteString.contains("ControlCenter"))
    }

    /// One row per account with a Claude window, in the sidebar's order, whatever its state; the word and what a
    /// click does come from the sidebar's own rule.
    @Test func entriesFollowTheSidebar() {
        let accounts = sidebar
        let entries = MenuBarMenu.entries(accounts: accounts, opening: ["client"], busy: ["perso"], appExists: { _ in true })
        #expect(entries.map(\.id) == ["ruben", "work", "client", "perso"])
        #expect(entries.map(\.title) == ["Show Ruben", "Open Work", "Opening Client…", "Updating Perso…"])
        #expect(entries.map(\.isEnabled) == [true, true, false, false])
        #expect(entries.map(\.tint) == [.orange, .blue, .green, .purple])
        for entry in entries {
            let account = accounts.first { $0.id == entry.id }!
            let othersOpen = accounts.contains { $0.id != entry.id && $0.isRunning }
            #expect(entry.action == SidebarAccountAction.of(account: account, opening: ["client"], busy: ["perso"], othersOpen: othersOpen, appExists: true))
        }
    }

    /// The title is the sidebar's word and the name, verb first as Mac menu commands read; a word that waits keeps its
    /// ellipsis at the end.
    @Test func titleCarriesTheSidebarWord() {
        let actions: [SidebarAccountAction] = [.open, .show, .opening, .updating, .rebuild]
        for action in actions {
            let label = try! #require(action.label)
            let title = try! #require(MenuBarMenu.title(name: "Work", action: action))
            #expect(title.contains(label.replacingOccurrences(of: "…", with: "")) && title.contains("Work"), "\(title)")
            #expect(title.hasSuffix("…") == label.hasSuffix("…"), "\(title)")
            #expect(title.filter { $0 == "…" }.count <= 1, "\(title)")
        }
        #expect(MenuBarMenu.title(name: "Work", action: .none) == nil)
        let missing = MenuBarMenu.entries(accounts: [account("Work")], opening: [], busy: [], appExists: { _ in false })
        #expect(missing.map(\.title) == ["Rebuild Work"])
        #expect(missing.map(\.isEnabled) == [true])
        // The primary opens Claude itself: no app of its own is not a missing app.
        let primary = MenuBarMenu.entries(accounts: [account("Ruben", primary: true)], opening: [], busy: [], appExists: { _ in false })
        #expect(primary.map(\.title) == ["Open Ruben"])
    }

    @Test func helpIsTheSidebarHelp() {
        let accounts = [account("Ruben", primary: true, running: true), account("New", session: false)]
        let entries = MenuBarMenu.entries(accounts: accounts, opening: [], busy: [], appExists: { _ in true })
        #expect(entries[0].help == SidebarAccountAction.show.help(for: accounts[0], othersOpen: false))
        #expect(entries[1].help == SidebarAccountAction.open.help(for: accounts[1], othersOpen: true))
        #expect(entries[1].help.hasPrefix("Opens Claude to log in."))
    }

    /// A menu action that says something brings the window forward, where the message shows; nothing else does.
    @Test func revealsWindowOnlyForANewMessage() {
        let m = UserMessage(title: "Work is being updated", detail: "Try again in a moment.")
        #expect(!MenuBarMenu.revealsWindow(before: nil, after: nil))
        #expect(MenuBarMenu.revealsWindow(before: nil, after: m))
        #expect(!MenuBarMenu.revealsWindow(before: m.id, after: m))
        #expect(MenuBarMenu.revealsWindow(before: UUID(), after: m))
        #expect(MenuBarMenu.notice(message: m, windowOpen: true) == nil)
        #expect(MenuBarMenu.notice(message: m, windowOpen: false) == "Work is being updated…")
        #expect(MenuBarMenu.notice(message: nil, windowOpen: false) == nil)
    }

    static let gib: Int64 = 1 << 30
    func mac(pressure: MemoryPressure.Level) -> MacMemory {
        // 832,307 pages of 16 KB: 12.7 GB used of 18 GB.
        MacMemory(physical: 18 * Self.gib, pageSize: 16_384,
                  pages: .init(internalPages: 700_000, purgeable: 0, external: 50_000, wired: 100_000, compressor: 32_307, free: 10_000),
                  swapUsed: 0, pressure: pressure)
    }

    /// The Mac's RAM in one line, the Usage screen's figures; a word when the kernel says it runs low. Never "memory":
    /// Memory is the notes.
    @Test func ramLine() {
        #expect(MenuBarMenu.ramLine(mac(pressure: .normal)) == "RAM: 12.7 GB of 18 GB used (71%)")
        #expect(MenuBarMenu.ramLine(mac(pressure: .warning)) == "RAM: 12.7 GB of 18 GB used (71%), running low")
        #expect(MenuBarMenu.ramLine(mac(pressure: .critical)) == "RAM: 12.7 GB of 18 GB used (71%), very low")
        #expect(MenuBarMenu.ramLine(nil) == nil)
    }

    /// The icon's eyes are open while an account is open or opening, like the creature in the sidebar.
    @Test func iconIsAwakeWhileAnAccountIsOpenOrOpening() {
        #expect(!MenuBarMenu.iconAwake(accounts: [account("Work")], opening: []))
        #expect(MenuBarMenu.iconAwake(accounts: [account("Work", running: true)], opening: []))
        #expect(MenuBarMenu.iconAwake(accounts: [account("Work")], opening: ["work"]))
        #expect(MenuBarMenu.iconLabel(openCount: 0) == "Brainmerge, no account open")
        #expect(MenuBarMenu.iconLabel(openCount: 1) == "Brainmerge, 1 account open")
        #expect(MenuBarMenu.iconLabel(openCount: 3) == "Brainmerge, 3 accounts open")
    }

    /// The fixed items, in the menu's order, and the only address the Star items open.
    @Test func fixedItemsAndTheStarAddress() {
        #expect(MenuBarMenu.fixedItems == ["Open Brainmerge", "Settings…", "Star on GitHub", "Quit Brainmerge"])
        #expect(BrainmergeLinks.repository.absoluteString == "https://github.com/ruben4reall/brainmerge")
        #expect(BrainmergeLinks.repository.scheme == "https")
    }

    /// Every place that offers the star opens that address and nothing else: the menu, Settings and the guide's last step.
    @Test func everyStarOpensTheRepository() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        for name in ["MenuBarContent.swift", "SettingsView.swift", "OnboardingView.swift"] {
            let source = try String(contentsOf: sources.appending(path: name), encoding: .utf8)
            let lines = source.split(separator: "\n").filter { $0.contains("MenuBarMenu.starTitle") }
            #expect(lines.count == 1, "\(name)")
            #expect(lines.allSatisfy { $0.contains("BrainmergeLinks.repository") }, "\(name)")
        }
    }

    @Test func noDashesInMenuCopy() {
        let accounts = sidebar
        var texts = MenuBarMenu.entries(accounts: accounts, opening: ["client"], busy: ["perso"], appExists: { _ in false }).flatMap { [$0.title, $0.help] }
        texts += [MenuBarMenu.ramLine(mac(pressure: .normal)), MenuBarMenu.ramLine(mac(pressure: .critical))].compactMap { $0 }
        texts += [MenuBarMenu.notice(message: UserMessage(title: "Something went wrong", detail: ""), windowOpen: false) ?? ""]
        texts += MenuBarMenu.fixedItems + [MenuBarMenu.settingTitle, MenuBarMenu.settingFootnote, MenuBarMenu.iconLabel(openCount: 2)]
        for text in texts { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)") }
        #expect(MenuBarMenu.settingTitle == "Show in the menu bar")
    }
}
