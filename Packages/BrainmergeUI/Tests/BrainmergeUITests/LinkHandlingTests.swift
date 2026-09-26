import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct LinkHandlingTests {
    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.git = OnboardingModelTests.Tools(true).availability
        return model
    }

    /// A cold launch from a link: the action waits for the first screen instead of acting on an empty model.
    @Test func aLinkBeforeReadyWaitsForTheFirstScreen() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.handle(URL(string: "brainmerge://usage")!)
        #expect(m.requestedScreen == nil)
        await m.launch(minimum: .zero)
        #expect(m.requestedScreen == .usage)
    }

    /// A link can arrive with the window closed (Brainmerge kept in the menu bar): a screen asks for the window.
    @Test func aScreenLinkAsksForTheWindow() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        await m.launch(minimum: .zero)
        #expect(m.windowRequests == 0)
        m.handle(URL(string: "brainmerge://usage")!)
        #expect(m.requestedScreen == .usage)
        #expect(m.windowRequests == 1)
    }

    final class Box: @unchecked Sendable { var ps = "" }

    /// Work still has to log in while Personal's window is open: the Log in sheet needs the window.
    @Test func anAccountThatMustLogInAsksForTheWindow() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let box = Box()
        box.ps = "4000001 1 1 \(e.claude.executable.path)"
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { box.ps }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.git = OnboardingModelTests.Tools(true).availability
        m.launchAccount = { _ in Issue.record("nothing opens before the sheet's Start") }
        await m.launch(minimum: .zero)
        m.handle(URL(string: "brainmerge://open/work")!)
        #expect(m.login?.title == "Log in to Work")
        #expect(m.windowRequests == 1)
    }

    /// The Accounts menu with the window closed: what the click has to say shows in the window, brought forward.
    @Test func aMessageFromTheAccountsMenuAsksForTheWindow() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Terminal"); request.surfaces = Surfaces(desktop: false, cli: true)
        _ = try e.manager.add(request)
        let m = model(e)
        await m.launch(minimum: .zero)
        await m.openFromMenu("terminal")?.value
        #expect(m.message?.title == "Terminal is Claude Code only")
        #expect(m.windowRequests == 1)
    }

    @Test func aLinkThatDoesNotParseDoesNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        await m.launch(minimum: .zero)
        m.handle(URL(string: "brainmerge://remove/ruben")!)
        #expect(m.requestedScreen == nil)
        #expect(m.message == nil)
        #expect(m.windowRequests == 0)
    }
}
