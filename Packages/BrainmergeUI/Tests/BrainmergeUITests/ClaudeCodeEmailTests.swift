import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// Which account Claude Code uses, shown on each account: read from the profiles, shown in the window, stored nowhere.
@MainActor @Suite struct ClaudeCodeEmailTests {
    func model(_ e: ManagerEnv, monitor: ProcessMonitor? = nil) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        return AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
    }

    /// Writes the account entry Claude Code keeps for display, next to what else the file holds.
    func record(_ email: String, displayName: String = "Ruben", in profile: CLIProfile, projects: [String] = []) throws {
        let keys = projects.map { "\"\($0)\":{}" }.joined(separator: ",")
        let json = #"{"projects":{\#(keys)},"userID":"u1","oauthAccount":{"emailAddress":"\#(email)","displayName":"\#(displayName)","organizationName":"\#(email)'s Organization"}}"#
        try Data(json.utf8).write(to: profile.accountFile)
    }

    func profile(_ e: ManagerEnv, _ slug: String) throws -> CLIProfile {
        CLIProfile(directory: try #require(try e.store.load().identity(slug: slug)).cliProfile(in: e.home.paths))
    }

    func account(_ m: AppModel, _ slug: String) -> Account? { m.accounts.first { $0.id == slug } }

    /// Every file under a folder whose bytes contain the text.
    func files(under root: URL, containing text: String) -> [String] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var hits: [String] = []
        for case let url as URL in walk {
            if let data = try? Data(contentsOf: url), data.range(of: Data(text.utf8)) != nil { hits.append(url.path) }
        }
        return hits
    }

    @Test func theEmailIsOnTheAccountAndNowhereElse() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        try record("agency.sentinel@example.com", in: e.primaryProfile, projects: [e.atelier])
        try record("ruben.sentinel@example.com", in: try profile(e, "agency"))
        let m = model(e)
        m.reload()
        #expect(account(m, "ruben")?.codeAccount == ClaudeCodeAccount(email: "agency.sentinel@example.com", displayName: "Ruben"))
        #expect(account(m, "agency")?.codeAccount?.email == "ruben.sentinel@example.com")

        // Everything that writes: an edit (state, Claude's instructions, the memory's list of accounts), a projects pass, a refresh.
        var edit = AccountEdit(account: try #require(account(m, "agency")), memory: "shared")
        edit.note = "Institute"
        await m.apply(edit, to: "agency")
        #expect(m.message == nil)
        m.wireNewProjects()
        m.refreshCodeAccounts()
        m.refreshMemory()
        #expect(account(m, "agency")?.codeAccount?.email == "ruben.sentinel@example.com")

        #expect(!(try String(contentsOf: e.home.paths.stateFile, encoding: .utf8)).contains("sentinel"))
        for slug in ["ruben", "agency"] {
            let claudeMD = try String(contentsOf: try profile(e, slug).claudeMD, encoding: .utf8)
            #expect(claudeMD.contains("<!-- brainmerge") || claudeMD.contains("brainmerge"))
            #expect(!claudeMD.contains("sentinel"), "\(slug)")
        }
        #expect(files(under: e.brain.root, containing: "sentinel").isEmpty)
        #expect(files(under: e.home.paths.appSupport, containing: "sentinel").isEmpty)
        #expect(files(under: e.home.paths.launchersDir, containing: "sentinel").isEmpty)
        #expect(files(under: e.home.paths.logsDir, containing: "sentinel").isEmpty)
        // Messages never carry it either.
        #expect(!(m.message.map { $0.title + $0.detail } ?? "").contains("sentinel"))
    }

    @Test func theEmailIsReadAtLaunchThenOnTheMinuteClockNotOnEveryReload() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let file = e.primaryProfile.accountFile
        try record("alex@example.com", in: e.primaryProfile, projects: [e.atelier])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: file.path)
        let m = model(e)
        m.reload()
        #expect(account(m, "ruben")?.codeAccount?.email == "alex@example.com")
        // A new login: the 3-second reload leaves the email alone (no flicker, nothing redrawn)...
        try record("sam@example.com", in: e.primaryProfile, projects: [e.atelier])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_100)], ofItemAtPath: file.path)
        #expect(!m.reload())
        #expect(account(m, "ruben")?.codeAccount?.email == "alex@example.com")
        // ...the minute clock and the window coming to the front read it again.
        m.refreshCodeAccounts()
        #expect(account(m, "ruben")?.codeAccount?.email == "sam@example.com")
        #expect(!m.reload())
        #expect(account(m, "ruben")?.codeAccount?.email == "sam@example.com")
        // Logged out: the entry goes, the email too.
        try Data(#"{"projects":{}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_200)], ofItemAtPath: file.path)
        m.refreshCodeAccounts()
        #expect(account(m, "ruben")?.codeAccount == nil)
    }

    @Test func aNewAccountIsReadAtItsFirstReload() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        // An account adopted with a login already in its folder: shown as soon as the list shows it, not a minute later.
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try record("work@example.com", in: try profile(e, "work"))
        m.reload()
        #expect(account(m, "work")?.codeAccount?.email == "work@example.com")
        // A removed account leaves nothing behind.
        try e.manager.remove(slug: "work", deleteData: false)
        m.reload()
        m.refreshCodeAccounts()
        #expect(account(m, "work") == nil)
    }

    @Test func anAccountWithClaudeCodeOffShowsNoEmail() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Desk"); request.surfaces = Surfaces(desktop: true, cli: false)
        _ = try e.manager.add(request)
        try record("desk@example.com", in: try profile(e, "desk"))
        let m = model(e)
        m.reload()
        m.refreshCodeAccounts()
        #expect(account(m, "desk")?.codeAccount == nil)
    }

    @Test func twoAccountsOnOneClaudeAccountAreFlagged() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        try record("Same@Example.com", in: e.primaryProfile, projects: [e.atelier])
        try record("same@example.com", in: try profile(e, "client"))
        let m = model(e)
        m.reload()
        #expect(m.duplicateCodeAccount(of: "ruben")?.id == "client")
        #expect(m.duplicateCodeAccount(of: "client")?.id == "ruben")
        #expect(m.duplicateCodeAccount(of: "work") == nil)
    }

    // MARK: Swapping names

    @Test func swappingNamesRenamesBothAccounts() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        try record("agency@example.com", in: e.primaryProfile, projects: [e.atelier])
        try record("ruben@example.com", in: try profile(e, "agency"))
        let m = model(e)
        m.reload()
        let ruben = try #require(account(m, "ruben"))
        let offer = try #require(CodeAccountNote.make(for: ruben, typedName: ruben.identity.name, among: m.accounts))
        #expect(offer.swapWith == CodeAccountNote.Other(slug: "agency", name: "Agency"))

        await m.swapNames("ruben", with: "agency")
        #expect(m.message == nil)
        #expect(account(m, "ruben")?.identity.name == "Agency")
        #expect(account(m, "agency")?.identity.name == "Ruben")
        #expect(m.busy.isEmpty && m.working == nil)
        #expect(m.appURL(of: "agency") == e.home.paths.launcherApp(name: "Ruben"))
        // The emails stay with their folders; the offer is gone now that the names match them.
        #expect(account(m, "ruben")?.codeAccount?.email == "agency@example.com")
        let after = try #require(account(m, "ruben"))
        #expect(CodeAccountNote.make(for: after, typedName: after.identity.name, among: m.accounts)?.swapWith == nil)
    }

    @Test func swappingWithAnOpenSecondarySaysSoAndChangesNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let agency = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        let exe = e.claude.executable.path, data = agency.desktopData(in: e.home.paths).path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        await m.swapNames("ruben", with: "agency")
        #expect(m.message?.title == "Agency is open")
        #expect(m.message?.detail == "Quit Agency first, then try again.")
        #expect(try e.store.load().identities.map(\.name) == ["Ruben", "Agency"])
        #expect(m.busy.isEmpty)
    }

    /// The primary follows the core's rule for any edit (IdentityManager.ensureEditable): it may stay open, since Claude
    /// itself is never rebuilt. Only the closed secondary's app is.
    @Test func swappingWhileThePrimaryRunsFollowsTheEditRule() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe)\n" }))
        m.reload()
        #expect(m.accounts.first { $0.id == "ruben" }?.isRunning == true)
        await m.swapNames("ruben", with: "agency")
        #expect(m.message == nil)
        #expect(try e.store.load().identities.map(\.name) == ["Agency", "Ruben"])
        #expect(m.appURL(of: "agency") == e.home.paths.launcherApp(name: "Ruben"))
        #expect(m.accounts.first { $0.id == "ruben" }?.isRunning == true)
        #expect(m.busy.isEmpty)
    }
}
