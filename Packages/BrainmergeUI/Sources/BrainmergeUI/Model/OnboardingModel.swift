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
    /// What opens the memory: the first notes app found on the Mac, else the folder.
    public var notesApp: String? = NotesApps.installed().first?.bundleIdentifier
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

    public func openAddedAccount() {
        guard let slug = addedSlug else { return }
        if othersOpen.isEmpty { app.open(slug) } else { app.quitOthers(then: slug) }
    }

    public private(set) var gitFound = false
    public private(set) var claudeCodeFound = false

    /// The All set row. Only the usual places are looked at (a Claude Code from npm under nvm lives elsewhere), so a miss
    /// says where it looked rather than that there is none.
    public static func claudeCodeRow(found: Bool) -> String {
        found ? "Claude Code: Found"
            : "Claude Code: Not found in the usual places. Your accounts still work in the Claude app. Install Claude Code to use them in a terminal."
    }

    /// What the setup shows as found. Git and Claude Code are looked for off the main thread: `xcode-select` is a process,
    /// and Claude Code's signature check reads the whole program.
    public func detect() async {
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

    public func next() { error = nil; move(by: 1) }

    /// "Continue" on the memory's step: a folder inside another git repository is refused here, with the reason, before
    /// anything is written.
    public func continueFromLocation() {
        let root: URL
        switch choice {
        case .newFolder: root = app.paths.defaultBrain
        case .existing(let url): root = url
        }
        if let problem = app.folderProblem(root) {
            error = UserMessage(title: "Choose another folder", detail: problem)
            return
        }
        next()
    }
    public func back() { error = nil; move(by: -1) }

    /// The steps shown: the git step only while Apple's tools are missing (as last checked, see `AppModel.checkGit`).
    public var steps: [Step] { Step.order.filter { $0 != .git || step == .git || !app.gitAvailable } }

    private func move(by offset: Int) {
        let order = Step.order
        guard var index = order.firstIndex(of: step) else { return }
        repeat {
            index += offset
            guard order.indices.contains(index) else { return }
        } while order[index] == .git && app.gitAvailable
        step = order[index]
    }

    /// "Check again", and every few seconds while the step shows: once the tools are in, the setup moves on.
    public func checkGit() async {
        if await app.checkGit(), step == .git { next() }
    }

    /// Apple's installer for the Command Line Tools: its own window, its own download from Apple.
    public func installAppleTools() { app.installAppleTools() }

    public func createBrain() throws {
        let root: URL
        switch choice {
        case .newFolder: root = app.paths.defaultBrain
        case .existing(let url): root = url
        }
        let brain = try Brain.initialize(at: root, language: language, availability: app.git)
        let notesApp = self.notesApp
        try app.store.update { state in
            state.brainPath = brain.root.path
            state.brainLanguage = language
            state.notesApp = notesApp
        }
        // A brain recreated or moved: every existing account is reattached to it (managed block, hook, memory links).
        let saved = try app.store.load()
        for identity in saved.identities { try app.manager.attachBrain(to: identity, state: saved) }
        app.reload()
    }

    /// "Done": the memory folder is only created now (going back leaves nothing behind), then the first account is adopted.
    public func finish() throws {
        try createBrain()
        try adoptPrimary()
    }

    /// The already-installed Claude becomes the first account. If Claude Code has never run, its folder is created.
    public func adoptPrimary() throws {
        // Each account's hooks call ~/.local/bin/brainmerge: the link is set up here, with this screen's consent.
        try app.linkCommandLineForHooks()
        _ = try CLIProfile.create(at: app.paths.primaryCLIProfile, inheritingFrom: nil)
        _ = try app.manager.adoptPrimary(name: primaryName.trimmingCharacters(in: .whitespaces))
        app.reload()
    }
}
