import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct OnboardingModelTests {
    func setup(withBrain: Bool = false, removePrimaryProfile: Bool = false) throws -> (ManagerEnv, AppModel, OnboardingModel) {
        let e = try ManagerEnv.make(withBrain: withBrain)
        if removePrimaryProfile { try FileManager.default.removeItem(at: e.home.paths.primaryCLIProfile) }
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false)
        let app = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        app.reload()
        return (e, app, OnboardingModel(app: app))
    }

    /// A git that is there or not, as a fake `xcode-select` says; `present` can change between checks.
    final class Tools: @unchecked Sendable {
        var present: Bool
        init(_ present: Bool) { self.present = present }
        var availability: GitAvailability {
            GitAvailability(shell: Shell { _, _, _, _ in ShellResult(status: self.present ? 0 : 2, stdout: "/Tools\n", stderr: "") },
                            isExecutable: { _ in true })
        }
    }

    @Test func theGitStepAppearsOnlyWhenGitIsMissingAndLeavesAfterCheckAgain() throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let tools = Tools(false)
        app.git = tools.availability
        onboarding.step = .howItWorks
        onboarding.next()
        #expect(onboarding.step == .git)
        onboarding.checkGit()
        #expect(onboarding.step == .git)
        tools.present = true
        onboarding.checkGit()
        #expect(onboarding.step == .brainLocation)
        onboarding.back()
        #expect(onboarding.step == .howItWorks)
    }

    @Test func withGitTheStepIsSkipped() throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.git = Tools(true).availability
        onboarding.step = .howItWorks
        onboarding.next()
        #expect(onboarding.step == .brainLocation)
    }

    @Test func allSetSaysWhetherGitAndClaudeCodeWereFound() throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.git = Tools(true).availability
        app.limitsBinary = { _ in .found("/opt/homebrew/bin/claude") }
        onboarding.detect()
        #expect(onboarding.gitFound && onboarding.claudeCodeFound)
        app.git = Tools(false).availability
        app.limitsBinary = { _ in .notFound }
        onboarding.detect()
        #expect(!onboarding.gitFound && !onboarding.claudeCodeFound)
    }

    @Test func detectsClaudeAndCountsProjects() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.detect()
        #expect(onboarding.claude?.version == "2.7032.0")
        #expect(onboarding.projectCount == 1)
        #expect(!onboarding.primaryName.isEmpty)
    }

    @Test func createsTheBrainWhereChosen() throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.language = .fr
        onboarding.notesApp = "md.obsidian"
        try onboarding.createBrain()
        #expect(try e.store.load().brainPath == e.home.paths.defaultBrain.path)
        #expect(try e.store.load().notesApp == "md.obsidian")
        #expect(try String(contentsOf: e.home.paths.defaultBrain.appending(path: "BRAIN.md"), encoding: .utf8).hasPrefix("# Cerveau partagé"))
        let other = e.home.url.appending(path: "Vault", directoryHint: .isDirectory)
        onboarding.choice = .existing(other)
        try onboarding.createBrain()
        #expect(try e.store.load().brainPath == other.path)
        #expect(app.brain?.root.path == other.path)
    }

    @Test func adoptsThePrimaryEvenWhenClaudeCodeWasNeverLaunched() throws {
        let (e, app, onboarding) = try setup(removePrimaryProfile: true); defer { e.home.remove() }
        try onboarding.createBrain()
        onboarding.primaryName = "Ruben"
        try onboarding.adoptPrimary()
        #expect(FileManager.default.fileExists(atPath: e.home.paths.primaryCLIProfile.path))
        #expect(app.accounts.first?.identity.name == "Ruben")
        #expect(app.accounts.first?.identity.isPrimary == true)
        #expect(!app.needsOnboarding)
    }

    @Test func recreatingTheBrainReattachesExistingAccounts() throws {
        let (e, app, onboarding) = try setup(withBrain: true); defer { e.home.remove() }
        onboarding.primaryName = "Ruben"
        try onboarding.adoptPrimary()
        let oldRoot = e.brain.root
        try FileManager.default.removeItem(at: oldRoot)
        app.reload()
        #expect(app.needsOnboarding)
        #expect(onboarding.missingBrainPath == oldRoot.path)
        let newRoot = e.home.url.appending(path: "Vault", directoryHint: .isDirectory)
        onboarding.choice = .existing(newRoot)
        try onboarding.createBrain()
        #expect(!app.needsOnboarding)
        let claudeMD = try String(contentsOf: e.primaryProfile.claudeMD, encoding: .utf8)
        #expect(claudeMD.contains(Brain(root: newRoot).root.path) && !claudeMD.contains(oldRoot.path))
    }

    @Test func errorClearsWhenMovingOn() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.error = UserMessage(title: "Oops", detail: "x")
        onboarding.next()
        #expect(onboarding.error == nil)
    }

    @Test func continueDoesNotTouchTheDiskBeforeDone() throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.next(); onboarding.next(); onboarding.next()     // welcome, how it works, location, first account
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.defaultBrain.path))
        onboarding.primaryName = "Ruben"
        try onboarding.finish()
        #expect(FileManager.default.fileExists(atPath: e.home.paths.defaultBrain.appending(path: "BRAIN.md").path))
        #expect(!app.needsOnboarding)
    }

    @Test func theGuidedSetupAddsASecondAccountAndEndsOnDemand() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        #expect(!onboarding.finished)
        onboarding.primaryName = "Ruben"
        try onboarding.finish()
        #expect(!app.needsOnboarding && !onboarding.finished)   // adopted, but the guide goes on
        onboarding.secondAccount.name = "Work"
        #expect(await onboarding.addSecondAccount())
        #expect(onboarding.addedSlug == "work")
        #expect(app.accounts.map(\.identity.slug) == ["ruben", "work"])
        onboarding.complete()
        #expect(onboarding.finished)
        // A later launch with everything in place skips the guide.
        #expect(OnboardingModel(app: app).finished)
    }

    @Test func theSecondAccountCanGetItsOwnMemory() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.primaryName = "Ruben"
        try onboarding.finish()
        onboarding.secondAccount.name = "Work"
        onboarding.secondAccount.memory = .own
        #expect(await onboarding.addSecondAccount())
        let state = try e.store.load()
        #expect(state.brains.map(\.id) == ["shared", "work"])
        #expect(state.identity(slug: "work")?.brain == "work")
        #expect(app.brains.count == 2)
        #expect(app.brainName(of: state.identity(slug: "work")!) == "Work")
    }

    @Test func stepsGoForwardAndBack() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        #expect(onboarding.step == .welcome)
        onboarding.next(); #expect(onboarding.step == .howItWorks)
        onboarding.next(); #expect(onboarding.step == .brainLocation)
        onboarding.next(); #expect(onboarding.step == .adopt)
        onboarding.next(); #expect(onboarding.step == .secondAccount)
        onboarding.next(); #expect(onboarding.step == .allSet)
        onboarding.next(); #expect(onboarding.step == .allSet)
        onboarding.back(); #expect(onboarding.step == .secondAccount)
        for _ in 0..<5 { onboarding.back() }
        #expect(onboarding.step == .welcome)
    }

    // MARK: After the launch splash

    /// An app model as the window gets it at launch: nothing loaded yet, the splash on screen.
    func unloadedApp(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false)
        return AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
    }

    @Test func aSetUpOwnerNeverLandsInTheGuidedSetupAfterTheSplash() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let app = unloadedApp(e)
        // Built with the window, before the first load: an empty model looks like a fresh Mac.
        let onboarding = OnboardingModel(app: app)
        #expect(!onboarding.finished)
        await app.launch(minimum: .zero)
        #expect(app.launchPhase == .ready)
        #expect(onboarding.finished)
    }

    @Test func everyWindowBuiltDuringTheSplashIsDecided() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let app = unloadedApp(e)
        let first = OnboardingModel(app: app), second = OnboardingModel(app: app)
        await app.launch(minimum: .zero)
        #expect(first.finished && second.finished)
        // A window opened later decides from the loaded model on its own.
        #expect(OnboardingModel(app: app).finished)
    }

    @Test func aFreshMacStillGetsTheGuidedSetupAfterTheSplash() async throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        let app = unloadedApp(e)
        let onboarding = OnboardingModel(app: app)
        await app.launch(minimum: .zero) { onboarding.decide() }
        #expect(app.launchPhase == .ready)
        #expect(!onboarding.finished)
    }
}
