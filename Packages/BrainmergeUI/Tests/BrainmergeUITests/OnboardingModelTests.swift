import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct OnboardingModelTests {
    func setup(withBrain: Bool = false, removePrimaryProfile: Bool = false,
               monitor: ProcessMonitor? = nil) throws -> (ManagerEnv, AppModel, OnboardingModel) {
        let e = try ManagerEnv.make(withBrain: withBrain)
        if removePrimaryProfile { try FileManager.default.removeItem(at: e.home.paths.primaryCLIProfile) }
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
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
        func clear() { lock.lock(); list = []; lock.unlock() }
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

    /// "Check again" that finds nothing says so, and shakes that line when asked again; the 5 s checks never say a word.
    @Test func checkAgainThatFindsNothingSaysSo() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let tools = Tools(false)
        app.git = tools.availability
        await onboarding.detect()
        onboarding.step = .howItWorks
        onboarding.next()
        await onboarding.checkGit()
        #expect(onboarding.gitNote.text == nil)
        await onboarding.checkGit(asked: true)
        #expect(onboarding.gitNote.text == OnboardingModel.gitStillMissing && onboarding.gitNote.repeats == 0)
        await onboarding.checkGit(asked: true)
        #expect(onboarding.gitNote.repeats == 1)
        tools.present = true
        await onboarding.checkGit(asked: true)
        #expect(onboarding.step == .brainLocation && onboarding.gitNote.text == nil)
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

    /// Only three places are looked at (a Claude Code from npm under nvm lives elsewhere): the row says so, never "none".
    @Test func claudeCodeNotFoundSaysOnlyTheUsualPlacesWereLookedAt() {
        #expect(OnboardingModel.claudeCodeRow(found: true) == "Claude Code: Found")
        #expect(OnboardingModel.claudeCodeRow(found: false)
                == "Claude Code: Not found in the usual places. Your accounts still work in the Claude app. Install Claude Code to use them in a terminal.")
    }

    @Test func claudeCodeIsLookedForOffTheMainThread() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let seen = Threads()
        // The signature check reads the whole program: never while the window waits.
        app.limitsBinary = { _ in seen.record(Thread.isMainThread); return .notFound }
        await onboarding.detect()
        #expect(seen.all == [false])
    }

    /// The projects are counted from Claude Code's .claude.json, which can be large: never while the window waits.
    @Test func projectsAreCountedOffTheMainThread() async throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        let seen = Threads()
        onboarding.countProjects = { _ in seen.record(Thread.isMainThread); return 3 }
        await onboarding.detect()
        #expect(seen.all == [false])
        #expect(onboarding.projectCount == 3)
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

    /// The guide can open over a first account that already exists: its memory folder went missing ("Your memory folder is
    /// missing." then the whole guide), or a demo forced the guide. The step shows that account as it is, with its own name,
    /// and asks for none (a name typed there was dropped: the account kept its own); Continue keeps it. The next step, with
    /// several accounts already there, adds another one, not a second.
    @Test func aGuideOverAnExistingFirstAccountShowsItAsItIs() async throws {
        let (e, app, _) = try setup(withBrain: true); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Personal")
        for name in ["Studio", "Client"] { _ = try e.manager.add(IdentityManager.AddRequest(name: name)) }
        try FileManager.default.removeItem(at: e.brain.root)
        app.reload()
        #expect(app.needsOnboarding)
        let onboarding = OnboardingModel(app: app)
        #expect(onboarding.firstAccount?.identity.name == "Personal")
        #expect(onboarding.primaryName == "Personal")
        #expect(onboarding.adoptSentence == "Personal is your first account, with everything it remembers.")
        onboarding.step = .adopt
        await onboarding.finish()
        #expect(onboarding.error == nil && onboarding.step == .secondAccount)
        #expect(app.accounts.map(\.identity.name) == ["Personal", "Studio", "Client"])
        #expect(onboarding.secondAccountTitle == "Add another account")
        onboarding.secondAccount.name = "Freelance"
        #expect(await onboarding.addSecondAccount())
        #expect(onboarding.secondAccountTitle == "Add another account")
    }

    /// On a fresh Mac the step asks for the first account's name, and the next one adds a second account, before and
    /// after it is added.
    @Test func aFreshGuideNamesTheFirstAccountThenAddsASecond() async throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        #expect(onboarding.firstAccount == nil)
        #expect(onboarding.adoptSentence == "The Claude already installed becomes your first account, with everything it remembers. Give it a name.")
        #expect(onboarding.secondAccountTitle == "Add a second account")
        onboarding.primaryName = "Personal"
        await onboarding.finish()
        #expect(onboarding.firstAccount?.identity.name == "Personal")
        #expect(onboarding.secondAccountTitle == "Add a second account")
        onboarding.secondAccount.name = "Work"
        #expect(await onboarding.addSecondAccount())
        #expect(onboarding.secondAccountTitle == "Add a second account")
    }

    /// "Continue" on the first account moves on at once: the memory folder and the account are made on the core queue while
    /// the next step slides in (its "Add account" waits for them), never while the window waits.
    @Test func doneMovesOnAtOnceWhileTheMemoryIsMade() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.step = .adopt
        onboarding.primaryName = "Ruben"
        let finishing = Task { await onboarding.finish() }
        while onboarding.step == .adopt { await Task.yield() }
        #expect(onboarding.step == .secondAccount)
        #expect(app.working != nil && app.needsOnboarding)
        await finishing.value
        #expect(app.working == nil && !app.needsOnboarding && onboarding.error == nil)
        #expect(app.accounts.first?.identity.name == "Ruben")
    }

    /// "Continue" on the first account never holds the window: the command line's lookup, the memory, the account and the
    /// reload after them (its `ps` and the account's `.claude.json`) all run off the main thread, so the page's fade plays.
    @Test func continueOnTheFirstAccountLeavesTheMainThreadFree() async throws {
        let seen = Threads()
        let (e, app, onboarding) = try setup(monitor: ProcessMonitor(psOutput: { seen.record(Thread.isMainThread); return "" }))
        defer { e.home.remove() }
        app.commandLine = { seen.record(Thread.isMainThread); return nil }
        seen.clear()
        onboarding.step = .adopt
        onboarding.primaryName = "Ruben"
        await onboarding.finish()
        #expect(onboarding.error == nil && app.accounts.first?.identity.name == "Ruben")
        #expect(seen.all.count >= 2 && !seen.all.contains(true), "\(seen.all)")
    }

    /// A second click on "Continue" while the first one's work runs changes nothing: one step on, one account.
    @Test func aSecondClickWhileTheMemoryIsMadeChangesNothing() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.step = .adopt
        onboarding.primaryName = "Ruben"
        async let first: Void = onboarding.finish()
        async let second: Void = onboarding.finish()
        _ = await (first, second)
        #expect(onboarding.step == .secondAccount && onboarding.error == nil)
        #expect(app.accounts.count == 1)
    }

    /// When the memory cannot be made, the guide comes back to the first account and says why.
    @Test func aFailedSetupComesBackToTheFirstAccount() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        let file = e.home.url.appending(path: "a-file")
        try Data("x".utf8).write(to: file)
        onboarding.choice = .existing(file.appending(path: "Brain", directoryHint: .isDirectory))
        onboarding.step = .adopt
        await onboarding.finish()
        #expect(onboarding.step == .adopt && onboarding.error != nil)
        #expect(app.needsOnboarding)
    }

    /// The notes apps on the Mac (and their icons) are looked up once, off the main thread, as the guide opens: the memory
    /// step then draws at once. The first one found is the default, unless the person already chose.
    @Test func notesAppsAreFoundOffTheMainThread() async throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        let seen = Threads()
        let obsidian = NotesApp(name: "Obsidian", bundleIdentifier: "md.obsidian", website: URL(string: "https://obsidian.md")!,
                                location: URL(fileURLWithPath: "/Applications/Obsidian.app"))
        onboarding.findNotesApps = { seen.record(Thread.isMainThread); return NotesApps.Found(apps: [obsidian], icons: [:]) }
        #expect(onboarding.notesApps == nil)
        await onboarding.detect()
        #expect(seen.all == [false])
        #expect(onboarding.notesApps?.apps == [obsidian] && onboarding.notesApp == "md.obsidian")
        // A choice made before the lookup ends is kept.
        let (e2, _, chosen) = try setup(); defer { e2.home.remove() }
        chosen.findNotesApps = { NotesApps.Found(apps: [obsidian], icons: [:]) }
        chosen.notesApp = nil
        await chosen.detect()
        #expect(chosen.notesApp == nil)
    }

    /// The welcome's own entrance plays once: going back to it shows it still.
    @Test func theWelcomeGreetsOnce() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        #expect(onboarding.greetedAt == nil)
        let first = Date(timeIntervalSinceReferenceDate: 1000)
        onboarding.greet(at: first)
        onboarding.greet(at: first.addingTimeInterval(30))
        #expect(onboarding.greetedAt == first)
    }

    @Test func errorClearsWhenMovingOn() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.error = UserMessage(title: "Oops", detail: "x")
        onboarding.next()
        #expect(onboarding.error == nil)
    }

    @Test func continueDoesNotTouchTheDiskBeforeDone() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.next(); onboarding.next(); onboarding.next()     // welcome, how it works, location, first account
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.defaultBrain.path))
        onboarding.primaryName = "Ruben"
        await onboarding.finish()
        #expect(onboarding.error == nil)
        #expect(FileManager.default.fileExists(atPath: e.home.paths.defaultBrain.appending(path: "BRAIN.md").path))
        #expect(!app.needsOnboarding)
    }

    @Test func theGuidedSetupAddsASecondAccountAndEndsOnDemand() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        #expect(!onboarding.finished)
        onboarding.primaryName = "Ruben"
        await onboarding.finish()
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

    /// Opening the added account from its card is remembered: the card never asks for it again while it opens, even
    /// before the new window is seen running.
    @Test func openingTheAddedAccountIsRemembered() async throws {
        let (e, app, onboarding) = try setup(monitor: ProcessMonitor(psOutput: { "" })); defer { e.home.remove() }
        onboarding.primaryName = "Ruben"
        await onboarding.finish()
        onboarding.secondAccount.name = "Work"
        #expect(await onboarding.addSecondAccount())
        let launched = CoreWorkTests.Log()
        app.launchAccount = { _, slug in launched.add(slug) }
        #expect(!onboarding.openedAdded)
        await onboarding.openAddedAccount()?.value
        #expect(onboarding.openedAdded && launched.entries == ["work"])
    }

    /// "Opening" holds only while an open is under way or the window is seen: a window that quits before the login, or
    /// one that never comes, gives the card its Open button back instead of "Opening" with no button for good.
    @Test func theAddedCardOffersOpenAgainOnceNothingOpens() async throws {
        let ps = CoreWorkTests.FakePS("")
        let (e, app, onboarding) = try setup(monitor: ProcessMonitor(psOutput: { ps.output })); defer { e.home.remove() }
        onboarding.primaryName = "Personal"
        await onboarding.finish()
        onboarding.secondAccount.name = "Work"
        #expect(await onboarding.addSecondAccount())
        let work = try #require(onboarding.addedAccount).identity
        // A pid above macOS's limit (99,999): no real process is ever matched.
        let window = "4000002 1 1000 \(e.claude.executable.path) --user-data-dir=\(work.desktopData(in: e.home.paths).path)"
        app.launchAccount = { _, _ in ps.output = window }
        await onboarding.openAddedAccount()?.value
        #expect(onboarding.addedAccount?.isRunning == true)
        #expect(onboarding.openedAdded)
        // Its Claude quits before the login: nothing opens any more, and the card asks again.
        ps.output = ""
        app.reload()
        #expect(onboarding.addedAccount?.isRunning == false)
        #expect(!onboarding.openedAdded)
        // A window that never comes: Opening from the click until the account's fallback, then Open again.
        app.openingFallback = .milliseconds(50)
        app.launchAccount = { _, _ in }
        let opening = onboarding.openAddedAccount()
        #expect(onboarding.openedAdded)
        await opening?.value
        for _ in 0..<1000 where onboarding.openedAdded { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!onboarding.openedAdded)
    }

    @Test func theSecondAccountCanGetItsOwnMemory() async throws {
        let (e, app, onboarding) = try setup(); defer { e.home.remove() }
        onboarding.primaryName = "Ruben"
        await onboarding.finish()
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

    /// The Connected check's ring spreads once per account, when it connects: going back and forth over the step shows the
    /// check still, with no second ring.
    @Test func theConnectedRingPlaysOncePerAccount() throws {
        let (e, _, onboarding) = try setup(); defer { e.home.remove() }
        #expect(onboarding.ringsForConnection(of: "work"))
        #expect(!onboarding.ringsForConnection(of: "work"))
        #expect(onboarding.ringsForConnection(of: "studio"))
        #expect(!onboarding.ringsForConnection(of: "studio"))
    }
}
