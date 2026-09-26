import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// Connections in the edit sheet: the browser profile that goes with an account, opened on a click, and the account's MCP
/// servers by name. A fake runner stands in for the browser: nothing is ever opened here.
@MainActor @Suite struct ConnectionsTests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [BrowserProfiles.Command] = []
        var commands: [BrowserProfiles.Command] { lock.lock(); defer { lock.unlock() }; return recorded }
        func record(_ c: BrowserProfiles.Command) { lock.lock(); recorded.append(c); lock.unlock() }
    }

    nonisolated static let chrome = InstalledBrowser(browser: .chrome, app: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                                         profiles: [BrowserProfile(browser: .chrome, directory: "Profile 2", name: "Work"),
                                                    BrowserProfile(browser: .chrome, directory: "Default", name: "Personal")])
    nonisolated static let work = BrowserChoice(browser: .chrome, directory: "Profile 2")
    nonisolated static let gone = BrowserChoice(browser: .chrome, directory: "Profile 9")

    /// Ruben and Client; with `clientRuns`, Client's Claude is open.
    func setUp(clientRuns: Bool = false) throws -> (ManagerEnv, AppModel, Recorder) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let ps = clientRuns ? "  900 1 120000 \(e.claude.executable.path) --user-data-dir=\(client.desktopData(in: e.home.paths).path)\n" : ""
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { ps }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.environment = [:]
        let recorder = Recorder()
        m.findBrowsers = { _ in [Self.chrome] }
        m.browserRunner = { recorder.record($0) }
        m.reload()
        return (e, m, recorder)
    }

    func edit(_ m: AppModel, _ slug: String = "client") throws -> AccountEdit {
        AccountEdit(account: try #require(m.accounts.first { $0.id == slug }), memory: AppState.defaultBrainID)
    }

    /// A pick the state could not take (its folder refuses the write) is never shown as saved: Save says so, and the
    /// account keeps what was saved before.
    @Test func aPickThatCouldNotBeSavedIsSaid() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        var edit = try edit(m)
        edit.browser = Self.work
        let folder = e.home.paths.appSupport
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let problem = await m.apply(edit, to: "client")
        #expect(problem != nil)
        #expect(m.accounts.first { $0.id == "client" }?.identity.browser == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(try e.store.load().identity(slug: "client")?.browser == nil)
    }

    /// Like every field of the sheet, the pick is kept on Save and dropped on Cancel.
    @Test func thePickIsSavedWithTheSheet() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        var edit = try edit(m)
        #expect(edit.browser == nil)
        edit.browser = Self.work
        #expect(try e.store.load().identity(slug: "client")?.browser == nil)
        #expect(await m.apply(edit, to: "client") == nil)
        #expect(try e.store.load().identity(slug: "client")?.browser == Self.work)
        #expect(m.accounts.first { $0.id == "client" }?.identity.browser == Self.work)
        #expect(try self.edit(m).browser == Self.work)
        edit.browser = nil
        #expect(await m.apply(edit, to: "client") == nil)
        #expect(try e.store.load().identity(slug: "client")?.browser == nil)
    }

    /// Picking a profile never touches the account's app: it is saved while the account runs.
    @Test func aPickAloneIsSavedWhileTheAccountRuns() async throws {
        let (e, m, _) = try setUp(clientRuns: true); defer { e.home.remove() }
        #expect(m.accounts.first { $0.id == "client" }?.isRunning == true)
        var edit = try edit(m)
        edit.browser = Self.work
        #expect(await m.apply(edit, to: "client") == nil)
        #expect(try e.store.load().identity(slug: "client")?.browser == Self.work)
    }

    /// An edit refused because the account runs saves nothing, the pick included: never half applied.
    @Test func aRefusedEditKeepsNoPick() async throws {
        let (e, m, _) = try setUp(clientRuns: true); defer { e.home.remove() }
        var edit = try edit(m)
        edit.name = "Clients"
        edit.browser = Self.work
        #expect(await m.apply(edit, to: "client") != nil)
        #expect(try e.store.load().identity(slug: "client")?.browser == nil)
        #expect(try e.store.load().identity(slug: "client")?.name == "Client")
    }

    @Test func opensThePickedProfile() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        #expect(m.openBrowserLabel(Self.work) == "Open Chrome (Work)")
        m.openBrowser(Self.work)
        m.manageConnectors(Self.work)
        #expect(recorder.commands == [
            BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["-na", "/Applications/Google Chrome.app", "--args", "--profile-directory=Profile 2"]),
            BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["-na", "/Applications/Google Chrome.app", "--args", "--profile-directory=Profile 2",
                                                                       "https://claude.ai/customize/connectors"]),
        ])
        #expect(m.message == nil)
    }

    @Test func connectorsOpenInTheDefaultBrowserWithoutAProfile() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        #expect(m.openBrowserLabel(nil) == nil)
        m.manageConnectors(nil)
        #expect(recorder.commands == [BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["https://claude.ai/customize/connectors"])])
    }

    /// A profile gone from the browser, or a browser gone from the Mac, is never opened: the browser would make a new empty
    /// profile, and the default browser may be logged into another account. The person is told instead.
    @Test func aProfileNoLongerThereIsNeverOpened() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        for choice in [Self.gone, BrowserChoice(browser: .edge, directory: "Default")] {
            #expect(m.openBrowserLabel(choice) == nil)
            m.openBrowser(choice)
            #expect(m.message?.title == "This browser profile is gone")
            m.message = nil
            m.manageConnectors(choice)
            #expect(m.message?.title == "This browser profile is gone")
            m.message = nil
        }
        #expect(recorder.commands.isEmpty)
    }

    /// Until the browsers are read, a picked profile cannot be told from a gone one: nothing opens and nothing is said.
    @Test func nothingOpensBeforeTheBrowsersAreRead() throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        #expect(m.installedBrowsers == nil)
        #expect(m.browserOptions(keeping: Self.work).isEmpty)
        m.manageConnectors(Self.work)
        m.openBrowser(Self.work)
        #expect(recorder.commands.isEmpty)
        #expect(m.message == nil)
    }

    /// The picker lists every profile, and keeps a pick whose profile is gone, said as such, so it can be changed.
    @Test func theOptionsKeepAPickThatIsGone() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        #expect(m.browserOptions(keeping: nil).map(\.label) == ["None", "Chrome · Work", "Chrome · Personal"])
        #expect(m.browserOptions(keeping: nil).map(\.choice) == [nil, Self.work, BrowserChoice(browser: .chrome, directory: "Default")])
        #expect(m.browserOptions(keeping: Self.work).count == 3)
        let kept = m.browserOptions(keeping: Self.gone)
        #expect(kept.map(\.label) == ["None", "Chrome · Work", "Chrome · Personal", "Chrome · Profile 9 (not found)"])
        #expect(kept.last?.choice == Self.gone)
        m.findBrowsers = { _ in [] }
        await m.loadConnections()
        #expect(m.browserOptions(keeping: nil).isEmpty)
        #expect(m.browserOptions(keeping: Self.gone).map(\.label) == ["None", "Chrome · Profile 9 (not found)"])
    }

    @Test func aDemoOpensNothing() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        m.environment = ["BRAINMERGE_CAPTURE": "1"]
        await m.loadConnections()
        m.manageConnectors(nil)
        m.openBrowser(Self.work)
        #expect(recorder.commands.isEmpty)
        #expect(m.message?.detail == "Brainmerge does not open a browser in a demo.")
    }

    @Test func marksServersOnlyThisAccountHas() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        let client = e.home.url.appending(path: ".claude-client/.claude.json")
        try Data(#"{"mcpServers":{"raylight":{"env":{"K":"SENTINEL"}},"shared":{}}}"#.utf8).write(to: client)
        try Data(#"{"mcpServers":{"shared":{}}}"#.utf8).write(to: e.home.url.appending(path: ".claude.json"))
        await m.loadConnections()
        #expect(m.mcpServers("client")?.codeUser == ["raylight", "shared"])
        #expect(m.onlyHere("client") == ["raylight"])
        #expect(m.onlyHere("ruben") == [])
        #expect(!"\(m.mcpInventories)".contains("SENTINEL"))
    }

    /// A short list of servers shows as it is; a long one folds, so the sheet stays short.
    /// The edit sheet opens once its connections are read, like the apps made by hand: it opens at its full size, and
    /// nothing moves under the pointer afterwards (the picker, the Open button, the servers).
    @Test func connectionsAreReadBeforeTheSheetOpens() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        #expect(m.installedBrowsers == nil)
        _ = await m.prepareEdit("client")
        #expect(m.installedBrowsers == [Self.chrome])
        #expect(m.mcpServers("client") != nil)
        let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BrainmergeUI/Screens")
        let section = try String(contentsOf: screens.appending(path: "ConnectionsSection.swift"), encoding: .utf8)
        #expect(!section.contains(".task") && !section.contains(".onAppear"), "the section reads nothing once shown")
        let accounts = try String(contentsOf: screens.appending(path: "AccountsView.swift"), encoding: .utf8)
        #expect(accounts.contains(#/editingApps = await model\.prepareEdit\(account\.id\)\s*\n\s*editing = account/#))
    }

    /// No Chrome, Arc, Brave or Edge profile at all: one faint line says why there is no picker.
    @Test func noBrowserProfileIsSaid() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        #expect(m.noBrowserNote == nil, "nothing before the browsers are read")
        await m.loadConnections()
        #expect(m.noBrowserNote == nil)
        m.findBrowsers = { _ in [InstalledBrowser(browser: .arc, app: URL(fileURLWithPath: "/Applications/Arc.app"), profiles: [])] }
        await m.loadConnections()
        #expect(m.noBrowserNote == "No Chrome, Arc, Brave or Edge profile was found on this Mac.")
        m.findBrowsers = { _ in [] }
        await m.loadConnections()
        #expect(m.noBrowserNote == "No Chrome, Arc, Brave or Edge profile was found on this Mac.")
    }

    @Test func onlyALongServerListFolds() {
        #expect(!ConnectionsSection.folds(serverCount: 6))
        #expect(ConnectionsSection.folds(serverCount: 7))
    }

    @Test func theGuidesReadAsWritten() {
        let lines = [AppModel.browserGuide(account: "Work"), AppModel.connectorsGuide, AppModel.demoConnectionsSentence, AppModel.noBrowserSentence]
        #expect(lines[0] == "Log the Claude extension of this profile into Work. Each account then has its own browser, with no logging out.")
        #expect(lines[1] == "Gmail, Calendar and Drive belong to each Claude account: connect the work Gmail in one account and the personal one in another.")
        for line in lines { #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}")) }
    }
}
