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
        // Hermetic: never the Mac's own xcode-select or Claude Code.
        app.git = Tools(true).availability
        app.limitsBinary = { _ in .notFound }
        app.reload()
        return (e, app, OnboardingModel(app: app))
    }

    /// Whether each call ran on the main thread.
    final class Threads: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Bool] = []
        var all: [Bool] { lock.lock(); defer { lock.unlock() }; return list }
        func record(_ onMain: Bool) { lock.lock(); list.append(onMain); lock.unlock() }
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

    @Test func theGitStepAppearsOnlyWhenGitIsMissingAndLeavesAfterCheckAgain() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let tools = Tools(false)
        app.git = tools.availability
        await onboarding.detect()
        onboarding.step = .howItWorks
        onboarding.next()
        #expect(onboarding.step == .git)
        await onboarding.checkGit()
        #expect(onboarding.step == .git)
        tools.present = true
        await onboarding.checkGit()
        #expect(onboarding.step == .brainLocation)
        onboarding.back()
        #expect(onboarding.step == .howItWorks)
    }

    @Test func withGitTheStepIsSkipped() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.git = Tools(true).availability
        await onboarding.detect()
        onboarding.step = .howItWorks
        onboarding.next()
        #expect(onboarding.step == .brainLocation)
    }

    @Test func allSetSaysWhetherGitAndClaudeCodeWereFound() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.git = Tools(true).availability
        app.limitsBinary = { _ in .found("/opt/homebrew/bin/claude") }
        await onboarding.detect()
        #expect(onboarding.gitFound && onboarding.claudeCodeFound)
        app.git = Tools(false).availability
        app.limitsBinary = { _ in .notFound }
        await onboarding.detect()
        #expect(!onboarding.gitFound && !onboarding.claudeCodeFound)
    }

    /// Installed but not Anthropic's build (a script from npm, say): it is there, so the setup never says to install it.
    @Test func aClaudeCodeNotSignedByAnthropicIsStillFound() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.limitsBinary = { _ in .notSigned("/opt/homebrew/bin/claude") }
        await onboarding.detect()
        #expect(onboarding.claudeCodeFound)
    }

    @Test func claudeCodeIsLookedForOffTheMainThread() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let seen = Threads()
        // The signature check reads the whole program: never while the window waits.
        app.limitsBinary = { _ in seen.record(Thread.isMainThread); return .notFound }
        await onboarding.detect()
        #expect(seen.all == [false])
    }

    @Test func detectsClaudeAndCountsProjects() async throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        await onboarding.detect()
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

    /// The page slides the way the guide moves: in from the right going on, from the left going back.
    @Test func movingRemembersItsDirection() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        #expect(onboarding.direction == 1)
        // Nowhere to go back to: nothing moves, the direction stays.
        onboarding.back()
        #expect(onboarding.step == .welcome && onboarding.direction == 1)
        onboarding.next(); #expect(onboarding.direction == 1)
        onboarding.back(); #expect(onboarding.direction == -1)
        onboarding.next(); #expect(onboarding.direction == 1)
        onboarding.back(); #expect(onboarding.step == .welcome && onboarding.direction == -1)
    }

    /// The progress dots: the steps behind in the accent, the current one a capsule, the ones ahead faint. One dot per step
    /// shown: with git there, no dot for the git step.
    @Test func dotsShowWhereTheGuideIs() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.next(); onboarding.next()
        #expect(onboarding.steps.map(onboarding.dot(for:)) == [.passed, .passed, .current, .future, .future, .future])
        #expect(onboarding.progressLabel == "Step 3 of 6")
        #expect(OnboardingModel.Dot.current.width == 18 && OnboardingModel.Dot.passed.width == 6 && OnboardingModel.Dot.future.width == 6)
        #expect(OnboardingModel.Dot.allCases.allSatisfy { $0.height == 6 })
    }

    /// Without Apple's tools the git step is the third dot, before the memory: the dots and VoiceOver follow the order
    /// shown, never the steps' numbering (git is numbered last so BRAINMERGE_ONBOARDING_STEP keeps its values).
    @Test func theGitStepIsADotInItsPlace() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        app.git = Tools(false).availability
        await onboarding.detect()
        onboarding.step = .howItWorks
        onboarding.next()
        #expect(onboarding.step == .git)
        #expect(onboarding.steps.map(onboarding.dot(for:)) == [.passed, .passed, .current, .future, .future, .future, .future])
        #expect(onboarding.progressLabel == "Step 3 of 7")
        // A later step (opened there, say): the git step is behind it.
        onboarding.step = .brainLocation
        #expect(onboarding.dot(for: .git) == .passed && onboarding.dot(for: .adopt) == .future)
        #expect(onboarding.progressLabel == "Step 4 of 7")
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
