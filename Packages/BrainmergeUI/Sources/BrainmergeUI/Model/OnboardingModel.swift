import AppKit
import Foundation
import Observation
import BrainmergeCore

@MainActor @Observable
public final class OnboardingModel {
    /// `git` comes last in the numbering so BRAINMERGE_ONBOARDING_STEP keeps its values; `order` places it before the memory.
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, howItWorks, brainLocation, adopt, secondAccount, allSet, git
        static let order: [Step] = [.welcome, .howItWorks, .git, .brainLocation, .adopt, .secondAccount, .allSet]
    }
    public enum BrainChoice: Equatable { case newFolder, existing(URL) }

    /// BRAINMERGE_ONBOARDING_STEP=0...3 opens the onboarding on that step (captures, demos).
    public var step: Step = Step(rawValue: Int(ProcessInfo.processInfo.environment["BRAINMERGE_ONBOARDING_STEP"] ?? "") ?? 0) ?? .welcome
    public var choice: BrainChoice = .newFolder
    public var language: BrainLanguage = .en
    /// What opens the memory: the first notes app found on the Mac (once `detect()` has looked), else the folder.
    public var notesApp: String? { didSet { notesAppChosen = true } }
    @ObservationIgnored private var notesAppChosen = false
    /// The notes apps on the Mac and their icons, looked up off the main thread as the guide opens (nil until then).
    public private(set) var notesApps: NotesApps.Found?
    /// How they are looked up; a fake in tests.
    @ObservationIgnored public var findNotesApps: @Sendable () -> NotesApps.Found = { NotesApps.find() }
    public var primaryName: String
    public private(set) var claude: ClaudeApp?
    public private(set) var projectCount = 0
    public var error: UserMessage?
    /// The guided setup stays on screen until the person closes it, even once the first account is in place.
    public var finished = false
    /// The optional second account of the guided setup.
    public var secondAccount = AddAccountForm()
    public private(set) var addedSlug: String?

    let app: AppModel

    public init(app: AppModel) {
        self.app = app
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        primaryName = full.split(separator: " ").first.map(String.init) ?? "Me"
        if primaryName.isEmpty { primaryName = "Me" }
        decide()
        // Built during the launch splash (every window open at launch): the model is still empty, so decide again
        // once it is loaded, right before the first screen appears, or a set-up owner would land in the guide.
        app.runBeforeReady { [weak self] in self?.decide() }
    }

    /// Everything already in place: no guide. BRAINMERGE_ONBOARDING_STEP forces it (captures, demos).
    public func decide() {
        finished = !app.needsOnboarding && ProcessInfo.processInfo.environment["BRAINMERGE_ONBOARDING_STEP"] == nil
    }

    public func complete() { finished = true }

    /// Creates the second account without opening it; the step then guides the login.
    public func addSecondAccount() async -> Bool {
        guard await app.add(secondAccount, open: false) else { return false }
        addedSlug = secondAccount.request.name.isEmpty ? nil : app.accounts.last?.id
        return addedSlug != nil
    }

    public var addedAccount: Account? { addedSlug.flatMap { slug in app.accounts.first { $0.id == slug } } }

    /// Other Claude windows must be closed before a new account logs in (the login link lands in the running one).
    public var othersOpen: [Account] { app.openAccounts.filter { $0.id != addedSlug } }

    /// The accounts whose Connected ring has spread: once each, when the step first shows them connected.
    @ObservationIgnored private var ringed: Set<String> = []
    /// True the first time only: the Connected check of `slug` spreads its ring now.
    public func ringsForConnection(of slug: String) -> Bool { ringed.insert(slug).inserted }

    public func openAddedAccount() {
        guard let slug = addedSlug else { return }
        if othersOpen.isEmpty { app.open(slug) } else { app.quitOthers(then: slug) }
    }

    public private(set) var gitFound = false
    public private(set) var claudeCodeFound = false

    /// What the setup shows as found. Git and Claude Code are looked for off the main thread: `xcode-select` is a process,
    /// and Claude Code's signature check reads the whole program.
    public func detect() async {
        let find = findNotesApps
        let found = await Task.detached(priority: .userInitiated) { find() }.value
        notesApps = found
        if !notesAppChosen { notesApp = found.apps.first?.bundleIdentifier }
        claude = try? ClaudeApp.detect(at: app.claudeAppURL)
        gitFound = await app.checkGit()
        let resolve = app.limitsBinary, home = app.paths.home
        claudeCodeFound = await Task.detached(priority: .userInitiated) { () -> Bool in
            // A Claude Code that is not Anthropic's build (a script from npm) is still there: never "install it".
            switch resolve(home) {
            case .found, .notSigned: return true
            case .notFound: return false
            }
        }.value
        let profile = CLIProfile(directory: app.paths.primaryCLIProfile)
        projectCount = (try? profile.projects().count) ?? 0
    }

    /// The saved memory folder that can't be found or is empty: onboarding says so and offers to choose another one.
    public var missingBrainPath: String? {
        guard app.brain == nil, let path = (try? app.store.load())?.brainPath else { return nil }
        return path
    }

    /// The way the guide last moved: 1 on, -1 back. The page slides in from that side (set before the step changes, so the
    /// page leaving and the page arriving read the same value).
    public private(set) var direction = 1

    public func next() { error = nil; move(by: 1) }
    public func back() { error = nil; move(by: -1) }

    /// The steps shown: the git step only while Apple's tools are missing (as last checked, see `AppModel.checkGit`).
    public var steps: [Step] { Step.order.filter { $0 != .git || step == .git || !app.gitAvailable } }

    /// Nowhere to go: nothing moves, and the direction stays.
    private func move(by offset: Int) {
        let order = Step.order
        guard var index = order.firstIndex(of: step) else { return }
        repeat {
            index += offset
            guard order.indices.contains(index) else { return }
        } while order[index] == .git && app.gitAvailable
        direction = offset
        step = order[index]
    }

    /// A progress dot: the steps behind in the accent, the current one a wider capsule, the ones ahead faint.
    public enum Dot: CaseIterable, Sendable {
        case passed, current, future
        public var width: CGFloat { self == .current ? 18 : 6 }
        public var height: CGFloat { 6 }
    }
    /// Behind or ahead in the order shown, never by the steps' numbering: git is numbered last but comes third.
    public func dot(for s: Step) -> Dot {
        guard let at = Step.order.firstIndex(of: s), let now = Step.order.firstIndex(of: step) else { return .future }
        return at == now ? .current : (at < now ? .passed : .future)
    }
    /// What VoiceOver reads for the dots: the place among the steps shown.
    public var progressLabel: String {
        let shown = steps
        return "Step \((shown.firstIndex(of: step) ?? 0) + 1) of \(shown.count)"
    }

    /// What "Check again" found when Apple's tools are still missing: said once, shaken when asked again.
    private(set) var gitNote = InlineProblem()
    public static let gitStillMissing = "Not there yet. Apple's installer takes a few minutes, and this step moves on by itself once it is done."

    /// "Check again" (`asked`), and every few seconds while the step shows: once the tools are in, the setup moves on.
    /// Only a click says that nothing changed; the clock's checks stay quiet.
    public func checkGit(asked: Bool = false) async {
        let found = await app.checkGit()
        if found {
            gitNote.show(nil)
            if step == .git { next() }
        } else if asked {
            gitNote.show(Self.gitStillMissing)
        }
    }

    /// Apple's installer for the Command Line Tools: its own window, its own download from Apple.
    public func installAppleTools() { app.installAppleTools() }

    public func createBrain() throws {
        try brainWork()()
        app.reload()
    }

    /// "Continue" on the first account: the guide moves on at once, and the memory folder (only created now: going back
    /// leaves nothing behind) and the first account are made on the core queue while the next step slides in. Its "Add
    /// account" waits for them (it is off while work runs). When they cannot be made, the guide comes back here and says why.
    public func finish() async {
        // A second click while the first one's work runs changes nothing.
        guard !finishing else { return }
        finishing = true
        defer { finishing = false }
        let brain = brainWork(), primary = primaryWork()
        next()
        if case .failure(let failure) = await app.outcome("Setting up your memory…", { try brain(); try primary() }) {
            if step == .secondAccount { back() }
            error = AppModel.sentence(for: failure)
        }
    }
    @ObservationIgnored private var finishing = false

    /// The already-installed Claude becomes the first account. If Claude Code has never run, its folder is created.
    public func adoptPrimary() throws {
        try primaryWork()()
        app.reload()
    }

    /// The memory folder where chosen, the setting saved, and every existing account reattached to it (managed block, hook,
    /// memory links): core work, with everything it needs read from the screen first.
    private func brainWork() -> @Sendable () throws -> Void {
        let root: URL
        switch choice {
        case .newFolder: root = app.paths.defaultBrain
        case .existing(let url): root = url
        }
        let language = self.language, notesApp = self.notesApp, git = app.git, store = app.store, manager = app.manager
        return {
            let brain = try Brain.initialize(at: root, language: language, availability: git)
            try store.update { state in
                state.brainPath = brain.root.path
                state.brainLanguage = language
                state.notesApp = notesApp
            }
            let saved = try store.load()
            for identity in saved.identities { try manager.attachBrain(to: identity, state: saved) }
        }
    }

    /// The first account, as core work. Each account's hooks call ~/.local/bin/brainmerge: the link is set up here, with
    /// this screen's consent.
    private func primaryWork() -> @Sendable () throws -> Void {
        let paths = app.paths, cli = app.commandLine(), manager = app.manager, name = primaryName.trimmingCharacters(in: .whitespaces)
        return {
            if let cli { try CLIInstaller.ensureLink(paths: paths, target: cli) }
            _ = try CLIProfile.create(at: paths.primaryCLIProfile, inheritingFrom: nil)
            _ = try manager.adoptPrimary(name: name)
        }
    }

    /// When the welcome first showed with its own entrance (no launch landing on it): it plays from here, once; going
    /// back to the welcome later finds it over.
    public private(set) var greetedAt: Date?
    public func greet(at date: Date) { if greetedAt == nil { greetedAt = date } }

}
