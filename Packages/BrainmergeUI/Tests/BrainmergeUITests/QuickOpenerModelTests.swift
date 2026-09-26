import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The quick opener's rows and keys act through the model's own paths: the Accounts menu's click, the memory's notes
/// app, the Usage screen. No test starts a program: the shell and the notes app are fakes.
@MainActor @Suite struct QuickOpenerModelTests {
    final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [[String]] = []
        var ps = ""
        var commands: [[String]] { lock.withLock { list } }
        func append(_ command: [String]) { lock.withLock { list.append(command) } }
    }

    final class Opened { var folders: [(URL, String?)] = [] }

    func model(_ e: ManagerEnv, runs: Runs, opened: Opened = Opened()) -> AppModel {
        let shell = Shell { executable, arguments, _, _ in
            runs.append([executable] + arguments)
            return ShellResult(status: 0, stdout: "", stderr: "")
        }
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, shell: shell, registerLaunchers: false,
                                      monitor: ProcessMonitor(psOutput: { runs.ps }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.git = OnboardingModelTests.Tools(true).availability
        m.openInNotes = { url, setting in opened.folders.append((url, setting)) }
        return m
    }

    @Test func rowsFollowTheSidebarWithClaudeCodeOnlyAccounts() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var work = IdentityManager.AddRequest(name: "Work"); work.note = "Acme"
        _ = try e.manager.add(work)
        var code = IdentityManager.AddRequest(name: "Terminal"); code.surfaces = Surfaces(desktop: false, cli: true)
        _ = try e.manager.add(code)
        let m = model(e, runs: Runs())
        await m.launch(minimum: .zero)
        #expect(m.quickOpenerRows.map(\.id) == ["ruben", "work", "terminal"])
        #expect(m.quickOpenerRows.map(\.note) == [nil, "Acme", nil])
        #expect(m.quickOpenerRows.last?.word == "Claude Code only")
    }

    /// Return is the Accounts menu's click: a closed account opens through macOS, as from its card.
    @Test func returnOpensAClosedAccount() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let runs = Runs()
        let m = model(e, runs: runs)
        await m.launch(minimum: .zero)
        await m.quickOpen(.open, on: "ruben")?.value
        #expect(runs.commands == [["/usr/bin/open", e.claude.url.path]])
        #expect(m.opening == ["ruben"])
        #expect(m.windowRequests == 0)
    }

    /// An account that still has to log in, with another Claude window open, goes through the Log in sheet, which asks
    /// before closing the others: the quick opener never changes which account a window is logged into.
    @Test func returnGoesThroughTheLogInSheet() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let runs = Runs()
        runs.ps = "4000001 1 1 \(e.claude.executable.path)"
        let m = model(e, runs: runs)
        m.launchAccount = { _ in Issue.record("nothing opens before the sheet's Start") }
        m.quitAccount = { _ in Issue.record("nothing closes before the sheet's Start") }
        await m.launch(minimum: .zero)
        #expect(m.quickOpen(.open, on: "work") == nil)
        #expect(m.login?.title == "Log in to Work")
        #expect(m.windowRequests == 1)
        #expect(runs.commands.isEmpty)
    }

    /// Cmd-Return opens the memory the account writes to, with the notes app of Settings.
    @Test func commandReturnOpensTheAccountsOwnMemory() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let workMemory = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        var client = IdentityManager.AddRequest(name: "Client"); client.brain = workMemory.id
        _ = try e.manager.add(client)
        try e.store.update { $0.notesApp = "md.obsidian" }
        let opened = Opened()
        let m = model(e, runs: Runs(), opened: opened)
        await m.launch(minimum: .zero)
        m.quickOpen(.memory, on: "client")
        m.quickOpen(.memory, on: "ruben")
        #expect(opened.folders.map(\.0.standardizedFileURL.path) == [workMemory.url.standardizedFileURL.path, e.brain.root.standardizedFileURL.path])
        #expect(opened.folders.map(\.1) == ["md.obsidian", "md.obsidian"])
        #expect(m.windowRequests == 0 && m.message == nil)
    }

    /// A memory folder moved away in the Finder: said in the window, with the way to Health, never a silent nothing.
    @Test func commandReturnOnAMissingMemorySaysSo() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let workMemory = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        var client = IdentityManager.AddRequest(name: "Client"); client.brain = workMemory.id
        _ = try e.manager.add(client)
        let opened = Opened()
        let m = model(e, runs: Runs(), opened: opened)
        await m.launch(minimum: .zero)
        try FileManager.default.removeItem(at: workMemory.url)
        m.quickOpen(.memory, on: "client")
        #expect(opened.folders.isEmpty)
        #expect(m.message?.title == "The Work memory is not where it was")
        #expect(m.message?.detail == "Its folder is gone from ~/Brain-work. Settings, Health, can point Brainmerge at where it is now.")
        #expect(m.message?.action == .openSettings)
        #expect(m.windowRequests == 1)
    }

    @Test func commandUShowsItsUsage() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let runs = Runs()
        let m = model(e, runs: runs)
        await m.launch(minimum: .zero)
        m.quickOpen(.usage, on: "work")
        #expect(m.requestedScreen == .usage)
        #expect(m.requestedUsage == "work")
        #expect(m.windowRequests == 1)
        #expect(runs.commands.isEmpty)
    }

    @Test func anAccountThatIsGoneDoesNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let runs = Runs(), opened = Opened()
        let m = model(e, runs: runs, opened: opened)
        await m.launch(minimum: .zero)
        for command in [QuickOpenerCommand.open, .memory, .usage] { #expect(m.quickOpen(command, on: "ghost") == nil) }
        #expect(runs.commands.isEmpty && opened.folders.isEmpty)
        #expect(m.windowRequests == 0 && m.requestedScreen == nil)
    }

    // MARK: The Usage screen's card

    /// Cmd-U brings the account's card into view once the usage is read, shared history included, then lets go. An
    /// account with no card (no Claude Code use) lets go once a read is done, so no later read scrolls on its own.
    @Test func theUsageScreenScrollsToTheAccountsCardOnce() {
        let usage = [AccountUsage(slugs: ["ruben"], names: ["Ruben"], tints: [.orange], summary: UsageSummary()),
                     AccountUsage(slugs: ["work", "client"], names: ["Work", "Client"], tints: [.blue, .green], summary: UsageSummary())]
        let read = Date(timeIntervalSince1970: 1000)
        #expect(UsageView.focus(requested: "client", usage: usage, refreshing: false, updated: read) == .scroll("work+client"))
        #expect(UsageView.focus(requested: "ruben", usage: usage, refreshing: true, updated: nil) == .scroll("ruben"))
        #expect(UsageView.focus(requested: nil, usage: usage, refreshing: false, updated: read) == nil)
        // Not read yet, or being read: it waits.
        #expect(UsageView.focus(requested: "code", usage: [], refreshing: false, updated: nil) == nil)
        #expect(UsageView.focus(requested: "code", usage: usage, refreshing: true, updated: read) == nil)
        #expect(UsageView.focus(requested: "code", usage: usage, refreshing: false, updated: read) == .drop)
    }

    // MARK: The panel

    /// Like Spotlight: centered on the screen, its top a fifth of the way down, never off the screen.
    @Test func thePanelSitsHighAndCenteredOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(QuickOpenerPanelController.frame(size: CGSize(width: 560, height: 420), in: screen) == CGRect(x: 440, y: 280, width: 560, height: 420))
        let second = CGRect(x: 1440, y: -200, width: 1000, height: 500)
        #expect(QuickOpenerPanelController.frame(size: CGSize(width: 560, height: 420), in: second) == CGRect(x: 1660, y: -200, width: 560, height: 420))
    }

    /// The keys act on the row picked among those that match; typing picks the first match again.
    @Test func thePanelActsOnThePickedRow() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let runs = Runs()
        let m = model(e, runs: runs)
        await m.launch(minimum: .zero)
        let panel = QuickOpenerPanelController(model: m)
        panel.search.query = "cl"
        panel.perform(.usage)
        #expect(m.requestedUsage == "client")
        panel.search.query = ""
        for _ in 0..<3 { panel.perform(.next) }
        #expect(panel.search.selection == 2)
        panel.perform(.previous)
        panel.perform(.usage)
        #expect(m.requestedUsage == "work")
        panel.search.query = "r"
        #expect(panel.search.selection == 0)
        panel.perform(.usage)
        #expect(m.requestedUsage == "ruben")
        panel.search.query = "zzz"
        panel.perform(.usage)
        #expect(m.requestedUsage == "ruben" && m.windowRequests == 3)
        #expect(runs.commands.isEmpty)
    }

    /// "Opening…" does nothing on Return, as in the sidebar: never a second launch on the same account.
    @Test func returnOnAnAccountThatIsOpeningDoesNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let runs = Runs()
        let m = model(e, runs: runs)
        await m.launch(minimum: .zero)
        m.markOpening("ruben", fallback: .seconds(60))
        let panel = QuickOpenerPanelController(model: m)
        panel.perform(.open)
        #expect(runs.commands.isEmpty)
        #expect(m.windowRequests == 0)
    }

    /// Before the screens are there, the press brings the window: there is nothing to list yet.
    @Test func aPressBeforeTheSetupBringsTheWindow() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e, runs: Runs())
        let panel = QuickOpenerPanelController(model: m)
        panel.press()
        #expect(m.windowRequests == 1)
        #expect(!panel.isShown)
    }

    /// Removing Brainmerge lets the shortcut go and forgets it on this Mac, like its other settings.
    @Test func anUninstallForgetsTheShortcut() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e, runs: Runs())
        let store = EphemeralSettings(), fake = FakeRegistrar()
        let opener = QuickOpener(defaults: store, registrar: fake)
        opener.setOn(true)
        m.quickOpener = opener
        await m.launch(minimum: .zero)
        #expect(await m.uninstall() != nil)
        #expect(fake.registered.isEmpty && !opener.isActive)
        for key in ["quickOpener.on", "quickOpener.keyCode", "quickOpener.modifiers", "quickOpener.key"] { #expect(store.object(forKey: key) == nil, "\(key)") }
    }

    // MARK: The shortcut's press

    /// Before the screens are there (the splash, the guide, an unreadable list), the press brings the window instead.
    @Test func thePressShowsClosesOrBringsTheWindow() {
        #expect(QuickOpenerPress.response(setupDone: true, panelShown: false) == .showPanel)
        #expect(QuickOpenerPress.response(setupDone: true, panelShown: true) == .closePanel)
        #expect(QuickOpenerPress.response(setupDone: false, panelShown: false) == .showWindow)
        #expect(QuickOpenerPress.response(setupDone: false, panelShown: true) == .closePanel)
    }
}
