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

    @Test func aLinkThatDoesNotParseDoesNothing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        await m.launch(minimum: .zero)
        m.handle(URL(string: "brainmerge://remove/ruben")!)
        #expect(m.requestedScreen == nil)
        #expect(m.message == nil)
    }
}
