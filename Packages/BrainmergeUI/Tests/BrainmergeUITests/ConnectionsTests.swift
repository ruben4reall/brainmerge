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

    func setUp() throws -> (ManagerEnv, AppModel, Recorder) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.environment = [:]
        let recorder = Recorder()
        m.findBrowsers = { _ in [Self.chrome] }
        m.browserRunner = { recorder.record($0) }
        m.reload()
        return (e, m, recorder)
    }

    @Test func thePickedProfileIsSavedOnTheAccount() async throws {
        let (e, m, _) = try setUp(); defer { e.home.remove() }
        await m.setBrowser("client", BrowserChoice(browser: .chrome, directory: "Profile 2")).value
        #expect(try e.store.load().identity(slug: "client")?.browser == BrowserChoice(browser: .chrome, directory: "Profile 2"))
        #expect(m.accounts.first { $0.id == "client" }?.identity.browser?.directory == "Profile 2")
        await m.setBrowser("client", nil).value
        #expect(try e.store.load().identity(slug: "client")?.browser == nil)
    }

    @Test func opensThatBrowserInThatProfile() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        await m.setBrowser("client", BrowserChoice(browser: .chrome, directory: "Profile 2")).value
        #expect(m.openBrowserLabel("client") == "Open Chrome (Work)")
        m.openBrowser("client")
        m.manageConnectors("client")
        #expect(recorder.commands == [
            BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["-na", "/Applications/Google Chrome.app", "--args", "--profile-directory=Profile 2"]),
            BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["-na", "/Applications/Google Chrome.app", "--args", "--profile-directory=Profile 2",
                                                                       "https://claude.ai/customize/connectors"]),
        ])
    }

    @Test func connectorsOpenInTheDefaultBrowserWithoutAProfile() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        #expect(m.openBrowserLabel("client") == nil)
        m.openBrowser("client")
        m.manageConnectors("client")
        #expect(recorder.commands == [BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["https://claude.ai/customize/connectors"])])
    }

    /// A profile that is gone from the browser is not opened: the browser would make a new empty one.
    @Test func aProfileNoLongerThereIsNotOpened() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        await m.loadConnections()
        await m.setBrowser("client", BrowserChoice(browser: .chrome, directory: "Profile 9")).value
        m.openBrowser("client")
        #expect(recorder.commands.isEmpty)
        #expect(m.message != nil)
    }

    @Test func aDemoOpensNothing() async throws {
        let (e, m, recorder) = try setUp(); defer { e.home.remove() }
        m.environment = ["BRAINMERGE_CAPTURE": "1"]
        await m.loadConnections()
        m.manageConnectors("client")
        #expect(recorder.commands.isEmpty)
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
    }
}
