import AppKit
import Foundation
import Observation
import BrainmergeCore

/// Whether an account's tinted copy of Claude matches the Claude installed. Launchers run the real Claude: never outdated.
public enum ClaudeVersionState: Equatable, Sendable {
    case notApplicable
    case current
    case outdated(installed: String, built: String)
}

public struct Account: Identifiable, Equatable, Sendable {
    public let identity: Identity
    public var isRunning: Bool
    /// Its Claude data folder holds a logged-in session (names of files only, see DesktopSession).
    public var hasSession: Bool = false
    public var claudeVersion: ClaudeVersionState = .notApplicable
    /// The account Claude Code last recorded in this account's folder, for display only (never stored, see ClaudeCodeAccount).
    /// Nil when Claude Code is off for this account, has not logged in, or logged out.
    public var codeAccount: ClaudeCodeAccount? = nil
    public var id: String { identity.slug }
    /// A desktop account that has not logged in yet.
    public var needsLogin: Bool { identity.surfaces.desktop && !hasSession }
    public var isOutdated: Bool { if case .outdated = claudeVersion { return true }; return false }
}

/// What "Check limits" found for an account: kept in memory only, never written anywhere, gone when Brainmerge quits.
public enum LimitsState: Equatable, Sendable {
    case checking
    /// The lines Claude Code printed for /usage, and when it was asked.
    case checked([LimitLine], at: Date)
    /// Why there is nothing to show, in one sentence.
    case refused(String)
}

/// Whether the window still shows the launch splash (the first load is running) or its screens.
public enum LaunchPhase: Equatable, Sendable { case loading, ready }

public struct UserMessage: Identifiable, Equatable, Sendable {
    /// What a message's button does: typed, so it never depends on a label.
    public enum Action: Equatable, Sendable {
        case quit(slug: String), quitOthersThenOpen(slug: String), getClaude, openSettings, moveToApplications, installAppleTools
    }
    public let id = UUID()
    public let title: String
    public let detail: String
    public let action: Action?
    public let actionLabel: String?
    public init(title: String, detail: String, action: Action? = nil, actionLabel: String? = nil) {
        self.title = title; self.detail = detail; self.action = action; self.actionLabel = actionLabel
    }
}

@MainActor @Observable
public final class AppModel {
    public private(set) var accounts: [Account] = [] { didSet { refreshSetupState() } }
    /// The default memory (the first of the list), initialized.
    public private(set) var brain: Brain? { didSet { refreshSetupState() } }
    /// Every memory the app knows, the default one first.
    public private(set) var brains: [MemoryFolder] = []
    /// The memory the Memory screen shows; nil or unknown means the default one.
    public var selectedBrainID: String? {
        didSet { if selectedBrainID != oldValue { refreshMemory() } }
    }
    public private(set) var claude: ClaudeApp?
    public private(set) var language: BrainLanguage = .en
    public private(set) var autoRebuild = true
    /// What opens the memory folder (see NotesApps.target).
    public private(set) var notesApp: String?
    /// The menu bar icon setting (see `showsMenuBarIcon` for whether it shows now).
    public private(set) var menuBarIcon = true { didSet { refreshSetupState() } }
    /// The settings saved from the app, each written to state.json on the core queue (see `save`).
    enum Setting: Hashable { case language, autoRebuild, notesApp, menuBarIcon, graphVault, graphMemory, browser(String) }
    /// Saves still waiting on the core queue, per setting: a reload meanwhile keeps the value shown, not the old file.
    private var pendingSaves: [Setting: Int] = [:]
    /// Tests only: runs on the core queue as a setting's save begins, before it waits for the state lock.
    @ObservationIgnored var saveBegins: @Sendable () -> Void = {}
    private func isSaving(_ setting: Setting) -> Bool { (pendingSaves[setting] ?? 0) > 0 }
    /// The Obsidian vault the Memory screen's graph shows, by its folder; nil shows the selected memory.
    public private(set) var graphVault: String? { didSet { if graphVault != oldValue { graphVaultGone = false } } }
    /// The chosen vault's folder was gone when last looked at: when it was chosen, or when the screen last opened.
    private var graphVaultGone = false
    /// The vaults in Obsidian's own list, read when the graph shows: those in a place macOS guards unlooked at, the
    /// others only while their folder exists.
    public private(set) var obsidianVaults: [URL] = []
    /// The process's environment, injectable in tests: captures and demos never show the icon.
    @ObservationIgnored public var environment = ProcessInfo.processInfo.environment { didSet { refreshSetupState() } }
    /// The guided setup is on screen (set by the window): until it is closed, the setup is not done.
    public var setupGuideShown = false {
        didSet {
            refreshSetupState()
            if setupGuideShown != oldValue { updateWatching() }
        }
    }
    /// The main window is open. Tracked once a window appeared: before that (the first load, tests) nothing follows it.
    public private(set) var windowOpen = false
    private var tracksWindow = false
    /// An uninstall is running: no clock may start again, whatever the window does.
    private var watchingSuspended = false
    /// A screen asked for from outside the window (the menu bar, the app menu with no window): the window shows it
    /// once its screens are there.
    public var requestedScreen: AppSection?
    public var message: UserMessage?
    /// Accounts launched and not seen running yet: cleared as soon as `reload()` sees their process,
    /// or after a few seconds if it never shows up.
    public private(set) var opening: Set<String> = []
    private var openingMarks: [String: Int] = [:]
    /// Accounts whose app bundle is being rebuilt, updated or removed right now: opening one would open a half-built app.
    /// Kept apart from `rebuilding`, whose marker must outlive the nested rebuild of an update.
    public private(set) var busy: Set<String> = []
    private var busyCount: [String: Int] = [:]
    /// A waiting sentence while heavy core work runs off the main thread: the work running now, while any remains.
    public var working: String? { workLabels.first?.label }
    private struct WorkLabel { let id: Int; let label: String }
    /// Every core work started and not finished yet, in the order it runs.
    private var workLabels: [WorkLabel] = []
    private var lastWorkID = 0
    /// Core work runs here, one at a time and in order: two changes never read and save the state at the same time.
    private let coreQueue = DispatchQueue(label: "ch.rubencatalao.brainmerge.core", qos: .userInitiated)
    /// The last process brought to the front by "Show" (observable in tests).
    public private(set) var lastShownProcess: Int32?
    public private(set) var lastMemorySave: Date?
    public private(set) var memoryEvents: [MemoryEvent] = []
    public private(set) var memoryCounts: [String: Int] = [:]
    public private(set) var projectCount = 0
    /// Usage per account (or per group of accounts with shared history), read from the local transcripts.
    public private(set) var usage: [AccountUsage] = []
    public private(set) var usageUpdatedAt: Date?
    public private(set) var usageRefreshing = false
    /// What each account's last "Check limits" found, by slug. Asked only on a click (see `checkLimits`).
    public private(set) var limits: [String: LimitsState] = [:]
    /// Finds the Claude Code to run and checks Anthropic's signature on it; a fake in tests.
    @ObservationIgnored public var limitsBinary: @Sendable (URL) -> ClaudeCodeBinary.Resolution = { home in
        ClaudeCodeBinary.resolve(candidates: ClaudeCodeBinary.candidates(home: home))
    }
    /// Starts Claude Code; a fake in tests, which never run the real one.
    @ObservationIgnored public var limitsRunner: ClaudeCodeLimits.Runner = ClaudeCodeLimits.shell
    /// Connections: the Chromium browsers installed with their profiles (nil until read), and each account's MCP servers
    /// by name, read when the edit sheet opens (see `loadConnections`).
    public internal(set) var installedBrowsers: [InstalledBrowser]?
    public internal(set) var mcpInventories: [String: MCPInventory] = [:]
    /// Finds the browsers and their profiles; a fake in tests.
    @ObservationIgnored public var findBrowsers: @Sendable (URL) -> [InstalledBrowser] = { BrowserProfiles.available(home: $0) }
    /// What Settings says about the accounts' hooks, read when it opens (see `refreshHooks`); nil until then.
    public private(set) var hooks: HooksSummary?
    /// The command line embedded in this copy of the app, which the link the hooks call points at; a fake in tests.
    @ObservationIgnored public var commandLine: () -> URL? = { AppModel.embeddedCLI }
    /// Opens a browser; a fake in tests, which never open one.
    @ObservationIgnored public var browserRunner: @Sendable (BrowserProfiles.Command) throws -> Void = { try Shell().check($0.path, $0.arguments) }
    /// The Mac's memory pressure, injectable in tests.
    public var memoryPressure: @Sendable () -> MemoryPressure.Level = { MemoryPressure.current() ?? .normal }
    /// The Mac's RAM figures, injectable in tests.
    public var readMacMemory: @Sendable (MemoryPressure.Level) -> MacMemory? = { MacMemory.read(pressure: $0) }
    /// The RAM of the open accounts together.
    public private(set) var totalRAMBytes: Int64 = 0
    /// The RAM each open account uses (instance and child processes, footprints like Activity Monitor). Kept apart
    /// from the accounts and compared at a 16 MB step: a few kilobytes moving with every `ps` do not redraw the interface.
    public private(set) var ramBySlug: [String: Int64] = [:]
    /// Claude Code sessions started outside any Claude window, which no account can claim.
    public private(set) var terminalUse = ProcessMonitor.TerminalUse(sessions: 0, bytes: 0)
    /// The Mac's RAM, redrawn only when a figure the screen shows (a tenth of a GB) or the pressure moves.
    public private(set) var macMemory: MacMemory?
    /// A sentence when the Mac is low on RAM, nil otherwise.
    public private(set) var memoryWarning: String?
    /// The disk space of each account, walked while the Usage screen shows (see `refreshDisk`). In memory only.
    public private(set) var disk: [String: AccountDisk] = [:]
    public private(set) var diskMeasuredAt: Date?
    public private(set) var diskMeasuring = false
    /// Walks one folder; the closure says when to stop. Injectable in tests.
    public var diskMeasure: @Sendable (DiskPlan.Root, @Sendable () -> Bool) -> DiskSize? = { root, cancelled in
        DiskUsage().size(of: root.url, privateOnly: root.privateOnly, skipping: root.skipping, isCancelled: cancelled)
    }
    /// Bumped by every change to the accounts: a walk that started before it is not taken as up to date.
    private var diskGeneration = 0
    /// The shortest time between two walks unless asked again.
    static let diskInterval: TimeInterval = 300
    private var logos: [String: NSImage] = [:]
    /// Automatic rebuilds already reported (slug and Claude version): one sentence, not one every five minutes.
    private var reportedRebuildFailures: Set<String> = []
    /// The Claude Code account of each account, kept apart from `accounts` (rebuilt from the state on every reload) and read
    /// again only by `refreshCodeAccounts()`. In memory only: the email is never written anywhere.
    private var codeAccounts: [String: ClaudeCodeAccount] = [:]
    /// Accounts whose Claude Code account was read at least once: a reload reads only the ones it has never seen.
    private var codeAccountsRead: Set<String> = []
    private var codeAccountCache = ClaudeCodeAccountCache()

    /// The live graph of the memory shown on the Memory screen; kept here so its layout survives switching screens.
    public let memoryGraph = MemoryGraphModel()

    public let paths: Paths
    public let store: StateStore
    public let manager: IdentityManager
    public let claudeAppURL: URL
    /// Whether git can run without Apple's install dialog (see GitAvailability). Tests put a fake one here.
    @ObservationIgnored public var git: GitAvailability = .shared
    /// The last answer, found off the main thread: at launch, then by `checkGit()` while a screen waits for Apple's tools.
    public private(set) var gitAvailable = true

    /// Asks again whether git is there, off the main thread (`xcode-select` is a process). The setup's git step and the
    /// Memory screen call it every few seconds while git is missing: once Apple's installer is done, they move on.
    @discardableResult
    public func checkGit() async -> Bool {
        let git = self.git
        let found = await Task.detached(priority: .userInitiated) { () -> Bool in
            git.invalidate()
            return git.isAvailable
        }.value
        if found != gitAvailable {
            gitAvailable = found
            // The history can be read now.
            if found { refreshMemory() }
        }
        return found
    }
    public static let historyNeedsGit = "History needs git. Install Apple's tools"

    /// Apple's installer for the Command Line Tools: its own window, its own download from Apple.
    public func installAppleTools() {
        let git = self.git
        Task.detached { try? git.install() }
    }

    /// Checks the Claude app the person picks in Settings (see ClaudeLocator). Tests put a fake one here.
    @ObservationIgnored public lazy var claudeLocator = ClaudeLocator(paths: paths)

    /// Remembers the Claude app picked in Settings, only when it is Anthropic's. Used from the next launch on.
    public func chooseClaude(_ url: URL) async -> UserMessage? {
        let locator = claudeLocator, store = self.store
        let refusal: String? = await Task.detached {
            do {
                try locator.validate(choice: url)
                try store.update { $0.claudeAppPath = url.path }
                return nil
            } catch BrainmergeError.claudeAppNotFound {
                return "This app is not Claude. Brainmerge only opens the official app."
            } catch { return String(describing: error) }
        }.value
        return refusal.map { UserMessage(title: "Claude was not changed", detail: $0) }
    }
    /// Where apps the person made are looked for: ~/Applications, and /Applications for the real home only.
    public var appFolders: [URL]
    private let watchers = Watchers()
    /// The clocks running now: the launch, the window and the menu bar icon can all ask, each clock runs once.
    public private(set) var watchedClocks: Set<Watchers.Clock> = []
    public var isWatching: Bool { !watchedClocks.isEmpty }

    /// `.loading` from the process start until the first load is done: the window shows the splash meanwhile.
    public private(set) var launchPhase: LaunchPhase = .loading { didSet { refreshSetupState() } }
    private var launchTask: Task<Void, Never>?
    private var beforeReady: [@MainActor () -> Void] = []
    /// Read off the main thread by the first load, then used once by `reload()` and `refreshMemory()`.
    private var prefetchedSnapshot: ProcessMonitor.Snapshot?
    private var prefetchedLog: (root: URL, entries: [BrainGit.Entry])?

    public init(paths: Paths, store: StateStore, manager: IdentityManager, claudeAppURL: URL) {
        self.paths = paths; self.store = store; self.manager = manager; self.claudeAppURL = claudeAppURL
        appFolders = ExistingApps.folders(for: paths)
    }

    /// The installed app's model: engine embedded in the bundle. The command line link is first set up at the end of the
    /// guided setup or from Settings; after that, each launch only mends it (see `loadFirstTime`).
    public static func live() -> AppModel {
        let paths = Paths.current()
        let launcher = Bundle.main.url(forAuxiliaryExecutable: "launcher") ?? LauncherBuilder.siblingLauncher()
        // Claude wherever it is installed, or where the person pointed Settings (read once per launch).
        let claude = ClaudeLocator.resolvedURL(paths: paths)
        let manager = IdentityManager(paths: paths, store: StateStore(paths: paths), launcherBinary: launcher,
                                      cliPath: CLIInstaller.link(in: paths).path, claudeAppURL: claude)
        let model = AppModel(paths: paths, store: StateStore(paths: paths), manager: manager, claudeAppURL: claude)
        // BRAINMERGE_MEMORY_PRESSURE=normal|warning|critical: for demos and screenshots.
        if let forced = ProcessInfo.processInfo.environment["BRAINMERGE_MEMORY_PRESSURE"] {
            let level: MemoryPressure.Level = forced == "critical" ? .critical : forced == "warning" ? .warning : .normal
            model.memoryPressure = { level }
        }
        // Captures and demos photograph the final screen: they load at once, as before. Otherwise the load runs behind the splash.
        if skipsSplash(environment: ProcessInfo.processInfo.environment) {
            model.reload()
            model.launchPhase = .ready
        }
        return model
    }

    // MARK: Launch

    /// Captures, README pictures and demos never show the splash (BRAINMERGE_CAPTURE, BRAINMERGE_SCREEN, BRAINMERGE_ONBOARDING_STEP).
    nonisolated static func skipsSplash(environment: [String: String]) -> Bool {
        ["BRAINMERGE_CAPTURE", "BRAINMERGE_SCREEN", "BRAINMERGE_ONBOARDING_STEP"].contains { environment[$0] != nil }
    }

    /// What the splash still waits once the load is done: a fast launch shows one step of the walk, a slow one waits no more.
    static func splashHold(loaded: Duration, minimum: Duration) -> Duration { max(.zero, minimum - loaded) }

    /// Runs `work` once the first load is done, right before the first screen appears (in the same main-actor turn as
    /// the switch to `.ready`, so nothing decided from an empty model ever shows). Nothing once ready: whatever is built
    /// after that sees loaded data already.
    public func runBeforeReady(_ work: @escaping @MainActor () -> Void) {
        if launchPhase == .loading { beforeReady.append(work) }
    }

    /// The first load, behind the splash, once per process however many windows ask: lets the splash draw its first frame,
    /// loads (`ps` and the memory's history off the main thread, so the walk keeps drawing), holds the splash for what
    /// remains of `minimum`, runs the work waiting for the first screen, then switches to `.ready`. Once ready, it does nothing.
    /// The load is an unstructured task: a window closed during the splash does not cancel it.
    public func launch(minimum: Duration = Theme.Launch.minimumVisible, beforeReady work: @escaping @MainActor () -> Void = {}) async {
        guard launchPhase == .loading else { return }
        runBeforeReady(work)
        let task = launchTask ?? Task { await loadBehindSplash(minimum: minimum) }
        launchTask = task
        await task.value
    }

    private func loadBehindSplash(minimum: Duration) async {
        let clock = ContinuousClock()
        let start = clock.now
        try? await Task.sleep(for: .milliseconds(16))   // the splash's first frame is on screen before any work; counts toward the minimum
        await loadFirstTime()
        let hold = Self.splashHold(loaded: start.duration(to: clock.now), minimum: minimum)
        if hold > .zero { try? await Task.sleep(for: hold) }
        let waiting = beforeReady
        beforeReady = []
        for work in waiting { work() }
        launchPhase = .ready
    }

    /// `reload()` with its two subprocesses (`ps`, and `git log` of the default memory) run off the main thread first.
    /// Once the guided setup has made an account, the link every hook calls is mended too: made when missing, pointed at
    /// this copy when the Brainmerge it pointed at was moved or trashed (never from a disk image, see
    /// `CLIInstaller.linkAtLaunch`). Before that, the setup asks first. Hooks an older Brainmerge wrote are brought up to
    /// date the same way, with no click: an update never keeps a hook that fails once the app is trashed. A demo home's
    /// link and hooks are left alone.
    private func loadFirstTime() async {
        let monitor = manager.monitor, store = self.store, paths = self.paths, manager = self.manager
        let demo = AppLifecycle.isCaptureOrDemo(environment: environment)
        let cli = demo ? nil : commandLine()
        let git = self.git
        let (snapshot, log, gitFound) = await Task.detached(priority: .userInitiated) { () -> (ProcessMonitor.Snapshot, (root: URL, entries: [BrainGit.Entry])?, Bool) in
            let state = try? store.load()
            if !demo, state?.identities.isEmpty == false {
                if let cli { try? CLIInstaller.linkAtLaunch(paths: paths, target: cli) }
                // Written only when one is not current: a launch never rewrites the settings of accounts already up to date.
                if let health = try? manager.hooksHealth(), health.contains(where: { $0.1 != .current }) { try? manager.repairHooks() }
            }
            let snapshot = (try? monitor.snapshot(measuring: true)) ?? ProcessMonitor.Snapshot(mains: [], all: [])
            let brain = state?.brainURL.map(Brain.init(root:)).flatMap { $0.isInitialized ? $0 : nil }
            return (snapshot, brain.map { (root: $0.root, entries: (try? BrainGit(brain: $0).log(limit: 200)) ?? []) }, git.isAvailable)
        }.value
        if gitFound != gitAvailable { gitAvailable = gitFound }
        prefetchedSnapshot = snapshot
        prefetchedLog = log
        reload()
        prefetchedSnapshot = nil
        prefetchedLog = nil
    }

    /// The command line embedded in the app (task 8), looked up by its exact name.
    nonisolated static var embeddedCLI: URL? {
        let exe = CLIInstaller.currentExecutable() ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return CLIInstaller.embeddedCLI(besideExecutable: exe)
    }

    /// An unreadable state is never a fresh install: it has its own screen, and the setup stays away.
    public var needsOnboarding: Bool { stateProblem == nil && (brain == nil || accounts.first(where: { $0.identity.isPrimary }) == nil) }

    /// Why state.json cannot be read, nil when it can (or does not exist yet).
    public private(set) var stateProblem: StateProblem?
    /// A copy from before the last change that this version can read, looked at when the problem is found.
    public private(set) var canRestorePreviousState = false

    /// Puts back the copy saved before the last change. The unreadable file is kept beside it. Off the main thread: the
    /// restore waits for the lock while the command line changes the state.
    public func restorePreviousState() async {
        let store = self.store
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do { try store.restorePrevious(); return nil } catch { return String(describing: error) }
        }.value
        if let failure { message = UserMessage(title: "Nothing was restored", detail: failure) }
        reload()
    }

    public func showStateFileInFinder() { revealInFinder(paths.stateFile) }
    public var openAccounts: [Account] { accounts.filter(\.isRunning) }

    /// The window's screens are there: past the splash, a memory and a first account, the guided setup closed.
    public private(set) var setupDone = false
    /// The menu bar icon shows: the setting, once the splash and the guided setup are over, never in a capture or a demo.
    /// Both are stored and written only when they change: the scenes and the app menu read them, and would otherwise be
    /// drawn again whenever an account opens or closes.
    public private(set) var showsMenuBarIcon = false

    private func refreshSetupState() {
        let done = launchPhase == .ready && !needsOnboarding && !setupGuideShown
        let shown = AppLifecycle.showsMenuBarIcon(setting: menuBarIcon, phase: launchPhase, setupDone: done, environment: environment)
        if done != setupDone { setupDone = done }
        if shown != showsMenuBarIcon { showsMenuBarIcon = shown }
    }

    /// The accounts of the menu bar's menu, with the sidebar's words.
    public var menuEntries: [MenuBarEntry] {
        MenuBarMenu.entries(accounts: accounts, opening: opening, busy: accountsBusy, appExists: { appURL(of: $0) != nil })
    }

    /// Reloads the state and the running instances: a single `ps` for every account. Only writes a property if
    /// its value changes, so as not to redraw the whole interface on every clock tick. Returns true if something changed.
    @discardableResult
    public func reload() -> Bool {
        var changed = false
        // With the window closed, only a reload notices that the setup or the icon changed: the clocks follow.
        let before = (needsOnboarding, showsMenuBarIcon)
        defer { if (needsOnboarding, showsMenuBarIcon) != before { updateWatching() } }
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
            if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value; changed = true }
        }
        set(\.claude, try? ClaudeApp.detect(at: claudeAppURL))
        let state: AppState
        do {
            state = try store.load()
            set(\.stateProblem, nil)
        } catch {
            set(\.stateProblem, StateProblem(error))
            set(\.canRestorePreviousState, store.canRestorePrevious)
            set(\.accounts, []); set(\.brain, nil)
            return changed
        }
        if !isSaving(.language) { set(\.language, state.brainLanguage) }
        if !isSaving(.autoRebuild) { set(\.autoRebuild, state.autoRebuild) }
        if !isSaving(.notesApp) { set(\.notesApp, state.notesApp) }
        if !isSaving(.menuBarIcon) { set(\.menuBarIcon, state.menuBarIcon) }
        if !isSaving(.graphVault) { set(\.graphVault, state.graphVault) }
        set(\.brains, state.brains)
        set(\.brain, state.brainURL.map(Brain.init(root:)).flatMap { $0.isInitialized ? $0 : nil })
        if let selected = selectedBrainID, state.brain(id: selected) == nil { selectedBrainID = state.defaultBrain?.id }
        // The first load shows the memory picked last time, while it still exists.
        else if selectedBrainID == nil, let first = state.graphMemory.flatMap(state.brain(id:)) ?? state.defaultBrain { selectedBrainID = first.id }
        let snapshot = prefetchedSnapshot ?? (try? manager.monitor.snapshot(measuring: true)) ?? ProcessMonitor.Snapshot(mains: [], all: [])
        let claudeApp = claude
        var memory: [String: Int64] = [:]
        codeAccountsRead.formIntersection(state.identities.map(\.slug))
        readCodeAccounts(of: state.identities.filter { !codeAccountsRead.contains($0.slug) })
        // Accounts changed outside the app (`brainmerge add` in a terminal) count like a change made here: walked again.
        if accounts.map(\.identity) != state.identities { diskChanged(); forgetLimits(outliving: state.identities) }
        set(\.accounts, state.identities.map { identity in
            let main = claudeApp.flatMap { app in snapshot.mains.first { ProcessMonitor.matches($0, identity: identity, paths: paths, claude: app) } }
            if let main { memory[identity.slug] = snapshot.memoryBytes(of: main.pid) }
            let session = identity.surfaces.desktop && DesktopSession.hasSession(dataDir: identity.desktopData(in: paths))
            return Account(identity: identity, isRunning: main != nil, hasSession: session, claudeVersion: Self.versionState(of: identity, claude: claudeApp),
                           codeAccount: codeAccounts[identity.slug])
        })
        let step: Int64 = 16 * 1024 * 1024
        func coarse(_ bytes: Int64) -> Int64 { (bytes + step / 2) / step }
        if memory.mapValues(coarse) != ramBySlug.mapValues(coarse) {
            ramBySlug = memory
            totalRAMBytes = memory.values.reduce(0, +)
            changed = true
        }
        let terminal = snapshot.terminalUse
        if terminal.sessions != terminalUse.sessions || coarse(terminal.bytes) != coarse(terminalUse.bytes) { terminalUse = terminal; changed = true }
        let level = memoryPressure()
        let mac = readMacMemory(level)
        if mac.map(Self.shownFigures) != macMemory.map(Self.shownFigures) { macMemory = mac; changed = true }
        set(\.memoryWarning, Self.memoryWarning(level: level, open: openAccounts.count, bytes: totalRAMBytes))
        // A window that showed up is no longer "opening".
        set(\.opening, opening.subtracting(openAccounts.map(\.id)))
        return changed
    }

    public func ramBytes(of slug: String) -> Int64 { ramBySlug[slug] ?? 0 }

    /// What the screen shows of the Mac's RAM, to a tenth of a GB, and the pressure.
    static func shownFigures(_ mac: MacMemory) -> [Int64] {
        let tenth: Int64 = (1 << 30) / 10
        return [mac.physical, mac.used, mac.appMemory, mac.wired, mac.compressed, mac.swapUsed].map { ($0 + tenth / 2) / tenth }
            + [Int64(mac.pressure.rawValue)]
    }

    // MARK: Which account Claude Code uses

    /// Reads again the account Claude Code recorded for every account (only the files that changed are parsed):
    /// at launch, on the minute clock and when the window comes back to the front. Never on the 3-second reload.
    public func refreshCodeAccounts() {
        let identities = accounts.map(\.identity)
        codeAccountsRead = []
        codeAccounts = codeAccounts.filter { slug, _ in identities.contains { $0.slug == slug } }
        readCodeAccounts(of: identities)
        let updated = accounts.map { account -> Account in
            var account = account
            account.codeAccount = codeAccounts[account.id]
            return account
        }
        if updated != accounts { accounts = updated }
    }

    /// An account with Claude Code off shows nothing, even if its folder holds an entry (the Claude app's Code tab can write one).
    private func readCodeAccounts(of identities: [Identity]) {
        for identity in identities {
            codeAccountsRead.insert(identity.slug)
            codeAccounts[identity.slug] = identity.surfaces.cli
                ? codeAccountCache.account(profile: CLIProfile(directory: identity.cliProfile(in: paths)))
                : nil
        }
    }

    /// Another account whose Claude Code uses the same email: one person twice, said as information.
    public func duplicateCodeAccount(of slug: String) -> Account? {
        guard let email = accounts.first(where: { $0.id == slug })?.codeAccount?.email else { return nil }
        return accounts.first { $0.id != slug && $0.codeAccount?.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    /// Only a tinted copy can lag behind the installed Claude.
    static func versionState(of identity: Identity, claude: ClaudeApp?) -> ClaudeVersionState {
        guard !identity.isPrimary, identity.surfaces.desktop, identity.iconMode == .tintedClone, let claude else { return .notApplicable }
        let built = identity.builtForClaudeVersion ?? "unknown"
        return built == claude.version ? .current : .outdated(installed: claude.version, built: built)
    }

    public var outdatedAccounts: [Account] { accounts.filter(\.isOutdated) }

    /// "Claude was updated to X. N accounts still run the old version." or nil.
    public var updateBanner: String? {
        guard let claude, !outdatedAccounts.isEmpty else { return nil }
        let n = outdatedAccounts.count
        return "Claude was updated to \(claude.version). \(n == 1 ? "1 account still runs" : "\(n) accounts still run") the old version."
    }

    // MARK: A real app per account

    /// The app that opens this account from the Dock: a secondary's launcher or copy, the primary's own app when it has one.
    public func appURL(of slug: String) -> URL? {
        accounts.first { $0.id == slug }?.identity.appURL(in: paths).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Apps the person made that also open this account (read off the main thread, never run). Nothing is stored:
    /// the edit sheet asks each time it opens.
    public func otherApps(opening slug: String) async -> [ExistingApp] {
        guard let identity = accounts.first(where: { $0.id == slug })?.identity else { return [] }
        let scanner = ExistingApps(paths: paths, claudeAppURL: claudeAppURL, folders: appFolders)
        return await Task.detached(priority: .userInitiated) { scanner.apps(opening: identity) }.value
    }

    /// Shows an app the person made in Finder, selected: the only thing Brainmerge does with it.
    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func revealApp(_ slug: String) {
        guard let url = appURL(of: slug) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Applies the edit sheet: name, color, photo, note and Dock icon (or the primary's own app) in one core call, then
    /// the memory if it changed. The primary may stay open for all of it but the memory: Claude itself is never rebuilt.
    /// Returns the problem it reported (also set as `message`), nil when everything was saved: the caller shows its own
    /// problem, never one another part of the app reported meanwhile. Everything that can refuse the edit is checked first.
    @discardableResult
    public func apply(_ edit: AccountEdit, to slug: String) async -> UserMessage? {
        guard let account = accounts.first(where: { $0.id == slug }) else { return nil }
        if let problem = edit.validate(existing: accounts.map(\.identity).filter { $0.slug != slug }) {
            return say(UserMessage(title: "Check the form", detail: problem))
        }
        let identity = account.identity
        let name = edit.trimmedName == identity.name ? nil : edit.trimmedName
        let tint = edit.tint == identity.tint ? nil : edit.tint
        let logo = edit.logo?.path == identity.logoPath ? nil : edit.logo
        let clearLogo = edit.logo == nil && identity.logoPath != nil
        let note = edit.trimmedNote == (identity.note ?? "") ? nil : edit.trimmedNote
        let iconMode: IconMode? = identity.isPrimary || edit.distinctIcon == (identity.iconMode == .tintedClone) ? nil : (edit.distinctIcon ? .tintedClone : .launcher)
        let ownApp: Bool? = identity.isPrimary && edit.ownApp != (identity.ownApp == true) ? edit.ownApp : nil
        let movesMemory = brain(of: identity)?.id != edit.memory
        // Moving the memory needs the account closed, the primary too: said before anything is saved, never half applied.
        if movesMemory, let open = runningSentence(slug) { return say(open) }
        if let old = identity.logoPath, logo != nil || clearLogo { logos[old] = nil }
        if name != nil || tint != nil || logo != nil || clearLogo || note != nil || iconMode != nil || ownApp != nil {
            let manager = self.manager
            if let failure = await change(slug, "Saving \(edit.trimmedName)…", touchesApp: true, primaryStaysOpen: true, {
                _ = try manager.update(slug: slug, name: name, tint: tint, logo: logo, note: note, iconMode: iconMode, clearLogo: clearLogo, ownApp: ownApp)
            }) { return failure }
        }
        // The browser profile touches no app: saved even while the account runs, only once the rest went through.
        if edit.browser != identity.browser { await setBrowser(slug, edit.browser).value }
        if movesMemory { return await setBrain(of: slug, to: edit.memory) }
        return nil
    }

    // MARK: Live updates of the tinted copies

    /// The accounts whose copy is being rebuilt right now: the automatic check leaves them alone.
    var rebuilding: Set<String> = []

    /// Every account whose app is being worked on, whatever the reason: the sidebar does not offer to open them.
    var accountsBusy: Set<String> { busy.union(rebuilding) }

    /// Quits the account if it is open, rebuilds its copy for the installed Claude, then reopens it.
    public func updateAccount(_ slug: String) async {
        guard let account = accounts.first(where: { $0.id == slug }), !accountsBusy.contains(slug) else { return }
        rebuilding.insert(slug)
        defer { rebuilding.remove(slug) }
        let wasRunning = account.isRunning
        if wasRunning {
            quit(slug)
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                reload()
                if accounts.first(where: { $0.id == slug })?.isRunning == false { break }
            }
        }
        let failure = await rebuild(slug)
        rebuilding.remove(slug)
        if wasRunning, failure == nil { open(slug) }
    }

    public func updateAll() async {
        for slug in outdatedAccounts.map(\.id) { await updateAccount(slug) }
    }

    /// "The Mac is low on RAM": a sentence, not an alarm, only when the kernel says so and accounts are open.
    static func memoryWarning(level: MemoryPressure.Level, open: Int, bytes: Int64) -> String? {
        guard level >= .warning, open > 0 else { return nil }
        let size = ByteFormat.ram(bytes)
        let accounts = open == 1 ? "1 open account uses" : "\(open) open accounts use"
        let severity = level == .critical ? "Your Mac is very low on RAM." : "Your Mac is running low on RAM."
        return "\(severity) \(accounts) \(size). Close the ones you don't use."
    }

    /// The memory shown on the Memory screen: the selected one when it exists and is initialized, else the default one.
    public var selectedBrain: Brain? {
        guard let id = selectedBrainID, let folder = brains.first(where: { $0.id == id }) else { return brain }
        let candidate = Brain(root: folder.url)
        return candidate.isInitialized ? candidate : brain
    }
    public var selectedFolder: MemoryFolder? { brains.first { $0.id == selectedBrainID } ?? brains.first }
    /// Shows a memory on the Memory screen and remembers it, like the graph's vault.
    @discardableResult
    public func selectBrain(_ id: String?) -> Task<Void, Never> {
        let chosen = id ?? brains.first?.id
        selectedBrainID = chosen
        return save(.graphMemory) { $0.graphMemory = chosen }
    }
    /// The memory an identity writes to, from the loaded list: the one it names while it exists, else the default one.
    public func brain(of identity: Identity) -> MemoryFolder? {
        identity.brain.flatMap { id in brains.first { $0.id == id } } ?? brains.first
    }
    public func brainName(of identity: Identity) -> String? { brain(of: identity)?.name }
    /// The accounts attached to a memory.
    public func accounts(using brainID: String) -> [Account] {
        accounts.filter { brain(of: $0.identity)?.id == brainID }
    }

    /// The selected memory's latest commits as sentences, the count per identity, the number of linked projects.
    public func refreshMemory() {
        guard let brain = selectedBrain, let folder = selectedFolder else { memoryEvents = []; memoryCounts = [:]; projectCount = 0; return }
        let entries = prefetchedLog.flatMap { $0.root == brain.root ? $0.entries : nil } ?? (try? BrainGit(brain: brain).log(limit: 200)) ?? []
        memoryEvents = MemoryFeed.events(from: Array(entries.prefix(50)), identities: accounts.map(\.identity))
        memoryCounts = MemoryFeed.counts(entries)
        lastMemorySave = entries.first?.date
        if let state = try? store.load() {
            let wiring = MemoryWiring(brain: brain, paths: paths, machineID: state.machineID)
            var projects: Set<String> = []
            for identity in state.identities(using: folder.id) {
                let profile = CLIProfile(directory: identity.cliProfile(in: paths))
                guard profile.exists else { continue }
                for status in (try? wiring.status(profile: profile)) ?? [] where status.state == .linked { projects.insert(status.name) }
            }
            projectCount = projects.count
        }
    }

    // MARK: Memories

    /// Creates a memory (a folder of notes) that accounts can be attached to.
    public func addBrain(name: String, path: URL?) async -> MemoryFolder? {
        let manager = self.manager, language = self.language
        return await perform("Creating the memory \(name)…") { try manager.addBrain(name: name, path: path, language: language) }
    }
    public func forgetBrain(_ id: String) async {
        let manager = self.manager
        _ = await perform("Forgetting the memory…") { try manager.forgetBrain(id: id) }
    }
    public func renameBrain(_ id: String, to name: String) async {
        let manager = self.manager
        _ = await perform("Renaming the memory…") { try manager.renameBrain(id: id, name: name) }
    }
    /// Attaches an account to a memory: its notes stay where they were written.
    @discardableResult
    public func setBrain(of slug: String, to id: String) async -> UserMessage? {
        let manager = self.manager
        let target = brains.first { $0.id == id }?.name ?? id
        let failure = await change(slug, "Attaching \(name(of: slug)) to \(target)…") { try manager.setBrain(of: slug, to: id) }
        refreshMemory()
        return failure
    }

    // MARK: Usage

    /// Reloads the transcripts off the main thread: the first pass can take a few seconds,
    /// after that only the modified files are read. Never any network, never any token.
    public func refreshUsage() async {
        guard !usageRefreshing else { return }
        usageRefreshing = true
        defer { usageRefreshing = false }
        let paths = self.paths
        let groups = UsageGrouping.groups(of: accounts.map(\.identity), paths: paths)
        let now = Date()
        let since = now.addingTimeInterval(-30 * 86_400)
        let computed: [AccountUsage] = await Task.detached(priority: .utility) {
            groups.map { group in
                let key = group.map(\.slug).joined(separator: "+")
                let reader = UsageReader(cacheFile: paths.appSupport.appending(path: "usage/\(key).json"))
                let profile = CLIProfile(directory: group[0].cliProfile(in: paths))
                let samples = (try? reader.read(profile: profile, since: since, now: now)) ?? []
                return AccountUsage(slugs: group.map(\.slug), names: group.map(\.name), tints: group.map(\.tint),
                                    summary: UsageSummary.make(samples, now: now))
            }
        }.value
        if usage != computed { usage = computed }
        usageUpdatedAt = now
    }

    // MARK: Limits, on click

    /// Every account with Claude Code on offers "Check limits", Claude Code only accounts included.
    public func canCheckLimits(_ slug: String) -> Bool {
        accounts.first { $0.id == slug }?.identity.surfaces.cli == true
    }

    static let demoLimitsSentence = "Brainmerge does not check limits in a demo."

    /// "Check limits": asks that account's own Claude Code what /usage shows, off the main thread, and keeps the answer in
    /// memory. Only the button calls this, never a clock. A capture or a demo never asks: it would run the owner's real
    /// Claude Code on the owner's real login.
    public func checkLimits(_ slug: String) async {
        guard let identity = accounts.first(where: { $0.id == slug })?.identity, identity.surfaces.cli,
              limits[slug] != .checking else { return }
        guard !AppLifecycle.isCaptureOrDemo(environment: environment) else {
            limits[slug] = .refused(Self.demoLimitsSentence)
            return
        }
        limits[slug] = .checking
        let home = paths.home, configDir = ClaudeCodeLimits.configDir(of: identity, paths: paths)
        let binary = limitsBinary, run = limitsRunner
        let outcome = await Task.detached(priority: .userInitiated) {
            ClaudeCodeLimits.check(home: home, configDir: configDir, binary: binary(home), run: run)
        }.value
        // The account may have gone, or become another login, while Claude Code answered.
        guard let now = accounts.first(where: { $0.id == slug })?.identity, isSameLogin(identity, now) else { return }
        if case .limits(let lines) = outcome {
            limits[slug] = .checked(lines, at: Date())
        } else {
            limits[slug] = .refused(outcome.sentence ?? "")
        }
    }

    /// Limits belong to one login: an account removed, added again under the same name, or moved to another Claude
    /// Code folder is another person, so what was found for the old one goes. A new name or color keeps it.
    private func forgetLimits(outliving identities: [Identity]) {
        let kept = limits.filter { slug, _ in
            guard let before = accounts.first(where: { $0.id == slug })?.identity,
                  let now = identities.first(where: { $0.slug == slug }) else { return false }
            return isSameLogin(before, now)
        }
        if kept.count != limits.count { limits = kept }
    }

    private func isSameLogin(_ before: Identity, _ now: Identity) -> Bool {
        before.id == now.id && now.surfaces.cli && before.cliProfile(in: paths) == now.cliProfile(in: paths)
    }

    // MARK: Disk

    /// Walks every account's folders off the main thread, unless a walk runs or the last one is recent and nothing
    /// changed since (`force` walks anyway). Cancelling the caller (the screen went away) stops the walk, and a walk
    /// stopped that way keeps nothing: the next visit walks again.
    public func refreshDisk(force: Bool = false, now: Date = Date()) async {
        guard !diskMeasuring else { return }
        if !force, let last = diskMeasuredAt, now.timeIntervalSince(last) < Self.diskInterval { return }
        diskMeasuring = true
        defer { diskMeasuring = false }
        let identities = accounts.map(\.identity), paths = self.paths, measure = diskMeasure, generation = diskGeneration
        let walk = Task.detached(priority: .utility) { () -> [String: AccountDisk]? in
            let plan = DiskPlan.plan(for: identities, paths: paths)
            let disks = DiskPlan.measure(plan) { root in measure(root, { Task.isCancelled }) }
            return Task.isCancelled ? nil : disks
        }
        // A detached task does not inherit the caller's cancellation: it is passed on by hand.
        guard let measured = await withTaskCancellationHandler(operation: { await walk.value }, onCancel: { walk.cancel() }) else { return }
        if disk != measured { disk = measured }
        if generation == diskGeneration { diskMeasuredAt = now }
    }

    /// Accounts or their apps changed: the next visit of the Usage screen walks again.
    func diskChanged() {
        diskGeneration += 1
        diskMeasuredAt = nil
    }

    // MARK: Photos

    /// An account's photo, decoded once and downscaled to display size.
    public func logo(for identity: Identity) -> NSImage? {
        guard let path = identity.logoPath else { return nil }
        if let cached = logos[path] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        let thumb = Self.thumbnail(image, side: 160)
        logos[path] = thumb
        return thumb
    }

    static func thumbnail(_ image: NSImage, side: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > side || size.height > side, size.width > 0, size.height > 0 else { return image }
        let scale = side / max(size.width, size.height)
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return NSImage(size: target, flipped: false) { rect in image.draw(in: rect); return true }
    }

    // MARK: Open, show, close

    /// Marks an account as opening until its window runs; the timer is only a fallback for a launch that never shows up,
    /// and an older click's timer never clears a newer mark.
    public func markOpening(_ slug: String, fallback: Duration = .seconds(4)) {
        opening.insert(slug)
        let mark = (openingMarks[slug] ?? 0) + 1
        openingMarks[slug] = mark
        Task {
            try? await Task.sleep(for: fallback)
            guard self.openingMarks[slug] == mark else { return }
            self.openingMarks[slug] = nil
            if self.opening.contains(slug) { self.opening.remove(slug) }
        }
    }

    /// Opens the account; if it's already running, brings its window to the front: never two instances on the same data folder.
    public func open(_ slug: String) {
        if let account = accounts.first(where: { $0.id == slug }), !account.identity.surfaces.desktop {
            message = UserMessage(title: "\(account.identity.name) is Claude Code only",
                                  detail: "This account has no Claude window. Use it with Claude Code in the terminal.")
            return
        }
        if let pid = runningProcess(for: slug) { show(pid); return }
        // Its app is being rebuilt, renamed or removed: opening it now would open a half-built app.
        if accountsBusy.contains(slug) {
            let name = name(of: slug)
            message = UserMessage(title: "\(name) is being updated", detail: "Brainmerge is working on \(name)'s app. Try again in a moment.")
            return
        }
        do { try manager.launch(slug: slug); markOpening(slug) } catch { present(error) }
        reload()
    }

    /// This account's Claude process, if it's running.
    func runningProcess(for slug: String) -> Int32? {
        guard let account = accounts.first(where: { $0.id == slug }), account.isRunning, let claude else { return nil }
        let processes = (try? manager.monitor.claudeProcesses()) ?? []
        return processes.first { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) }?.pid
    }

    /// Brings an account's Claude forward with its window. Claude keeps running once its window is closed, and bringing
    /// the process forward shows no window: when its app is the only one of its kind running, it is opened again, as a
    /// Dock click does, and Claude shows its window (see WindowReveal). Only a Claude process is ever touched, never
    /// whatever else took the number `ps` gave since.
    func show(_ pid: Int32) {
        lastShownProcess = pid
        guard let app = NSRunningApplication(processIdentifier: pid), WindowReveal.isClaude(bundleIdentifier: app.bundleIdentifier) else { return }
        NSApp?.yieldActivation(to: app)
        app.activate()
        let running = NSWorkspace.shared.runningApplications.map { (pid: $0.processIdentifier, bundle: $0.bundleURL) }
        // Reopening an app that has just quit would start it again, possibly as another account: only a live process.
        if case .reopen(let bundle) = WindowReveal.of(pid: pid, bundle: app.bundleURL, running: running), !app.isTerminated {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        }
    }

    /// A clean quit: AppKit's termination event when the instance is a known app, otherwise SIGTERM.
    public func quit(_ slug: String) {
        guard let account = accounts.first(where: { $0.id == slug }) else { return }
        if let pid = runningProcess(for: slug), let app = NSRunningApplication(processIdentifier: pid), app.terminate() {
            Task { try? await Task.sleep(for: .seconds(1)); self.reload() }
            return
        }
        do { try manager.quit(account.identity) } catch { present(error) }
        reload()
    }

    /// Closes the other open accounts, then opens this one: logging in a new account needs to be alone.
    public func quitOthers(then slug: String) {
        for account in openAccounts where account.id != slug { try? manager.quit(account.identity) }
        Task { try? await Task.sleep(for: .seconds(2)); self.reload(); self.open(slug) }
    }

    /// A brand-new account opens Claude to log in. The browser's login link opens in the Claude instance
    /// that's already running: if there is one, we ask to close it first. An adopted account is already logged in.
    func openNewAccount(_ identity: Identity) {
        let others = openAccounts.filter { $0.id != identity.slug }
        if identity.desktopDataPath == nil, !others.isEmpty {
            let names = others.map(\.identity.name).joined(separator: ", ")
            message = UserMessage(title: "Close your other Claude windows first",
                                  detail: "\(identity.name) needs to log in. The login link from your browser opens in the Claude window that is already running (\(names)), so quit it first, then open \(identity.name) and log in.",
                                  action: .quitOthersThenOpen(slug: identity.slug), actionLabel: "Quit and open \(identity.name)")
            return
        }
        open(identity.slug)
    }

    // MARK: Heavy core work, off the main thread

    /// Launchers, tinted copies, deletions: run off the main thread, with a waiting sentence; nil and a message on failure.
    func perform<T: Sendable>(_ label: String, _ work: @escaping @Sendable () throws -> T) async -> T? {
        switch await outcome(label, work) {
        case .success(let value): return value
        case .failure(let error): present(error); return nil
        }
    }

    /// Runs core work on the core queue, after any work already there, with its waiting sentence, then reloads.
    /// The outcome is returned as it is: the caller decides what to say.
    func outcome<T: Sendable>(_ label: String, _ work: @escaping @Sendable () throws -> T) async -> Result<T, Error> {
        lastWorkID += 1
        let id = lastWorkID
        workLabels.append(WorkLabel(id: id, label: label))
        defer { workLabels.removeAll { $0.id == id } }
        let queue = coreQueue
        let result: Result<T, Error> = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Result { try work() }) }
        }
        // Every change to accounts, their folders or their apps runs here, the automatic rebuilds included.
        diskChanged()
        reload()
        return result
    }

    /// Shows a message and returns it, for callers that report their own problem.
    @discardableResult
    func say(_ sentence: UserMessage) -> UserMessage {
        message = sentence
        return sentence
    }

    /// Any change to an open account is refused, with its real name, before calling the engine.
    /// `touchesApp`: the work deletes and rebuilds (or removes) the account's app, so the account is busy meanwhile.
    /// Only a secondary account with a Claude window opens through its own app: the primary opens Claude itself.
    /// `primaryStaysOpen`: the work never touches Claude (names, colors, notes, the primary's own app), so an open
    /// primary is changed as it is, without asking to quit it.
    /// Returns the problem it reported, nil when the work was done.
    @discardableResult
    func change(_ slug: String, _ label: String, touchesApp: Bool = false, primaryStaysOpen: Bool = false,
                _ work: @escaping @Sendable () throws -> Void) async -> UserMessage? {
        let identity = accounts.first { $0.id == slug }?.identity
        let mayStayOpen = primaryStaysOpen && identity?.isPrimary == true
        if !mayStayOpen, let open = runningSentence(slug) { return say(open) }
        let marks = touchesApp && identity.map { !$0.isPrimary && $0.surfaces.desktop } == true
        if marks { markBusy(slug, true) }
        defer { if marks { markBusy(slug, false) } }
        if case .failure(let error) = await outcome(label, work) { return say(Self.sentence(for: error)) }
        return nil
    }

    /// Counted, so that two overlapping changes of one account do not clear each other's mark.
    func markBusy(_ slug: String, _ on: Bool) {
        let count = max(0, (busyCount[slug] ?? 0) + (on ? 1 : -1))
        busyCount[slug] = count == 0 ? nil : count
        if count > 0, !busy.contains(slug) { busy.insert(slug) }
        if count == 0, busy.contains(slug) { busy.remove(slug) }
    }

    func name(of slug: String) -> String { accounts.first { $0.id == slug }?.identity.name ?? slug }

    public func remove(_ slug: String, deleteData: Bool) async {
        let manager = self.manager
        await change(slug, "Removing \(name(of: slug))…", touchesApp: true) { try manager.remove(slug: slug, deleteData: deleteData) }
    }

    @discardableResult
    public func rebuild(_ slug: String) async -> UserMessage? {
        let manager = self.manager
        return await change(slug, "Rebuilding \(name(of: slug))…", touchesApp: true, primaryStaysOpen: true) { try manager.rebuild(slug: slug) }
    }

    /// Adds an account from the form; returns true if it's done, otherwise sets the message.
    /// `open: false` only creates the account (the guided setup opens it at the right moment).
    @discardableResult
    public func add(_ form: AddAccountForm, open: Bool = true) async -> Bool {
        if let problem = form.validate(existing: accounts.map(\.identity)) {
            message = UserMessage(title: "Check the form", detail: problem); return false
        }
        let manager = self.manager
        let request = form.request
        guard let identity = await perform("Adding \(request.name)…", { try manager.add(request) }) else { return false }
        if open, identity.surfaces.desktop { openNewAccount(identity) }
        return true
    }

    public func rename(_ slug: String, to name: String) async {
        var form = AddAccountForm(); form.name = name
        if let problem = form.validate(existing: accounts.map(\.identity).filter { $0.slug != slug }) {
            message = UserMessage(title: "Check the form", detail: problem); return
        }
        let manager = self.manager; let clean = form.trimmedName
        await change(slug, "Renaming to \(clean)…", touchesApp: true, primaryStaysOpen: true) { _ = try manager.update(slug: slug, name: clean, tint: nil, logo: nil) }
    }
    /// Swaps two accounts' names in one step (the edit sheet offers it when the names look swapped against the emails
    /// Claude Code uses). A rename rebuilds a secondary's app, so an open secondary is said and nothing changes; whether
    /// the primary may stay open is the core's rule for any edit (`IdentityManager.ensureEditable`).
    /// Returns the problem it reported, nil when both accounts were renamed.
    @discardableResult
    public func swapNames(_ slug: String, with other: String) async -> UserMessage? {
        guard let one = accounts.first(where: { $0.id == slug }), let two = accounts.first(where: { $0.id == other }), slug != other else { return nil }
        for account in [one, two] where !account.identity.isPrimary {
            if let open = runningSentence(account.id) { return say(open) }
        }
        let marked = [one, two].filter { !$0.identity.isPrimary && $0.identity.surfaces.desktop }.map(\.id)
        for id in marked { markBusy(id, true) }
        defer { for id in marked { markBusy(id, false) } }
        let manager = self.manager
        if case .failure(let error) = await outcome("Swapping the names of \(one.identity.name) and \(two.identity.name)…", { try manager.swapNames(slug, with: other) }) {
            return say(Self.sentence(for: error))
        }
        return nil
    }

    public func changeTint(_ slug: String, to tint: Tint) async {
        let manager = self.manager
        await change(slug, "Recoloring \(name(of: slug))…", touchesApp: true, primaryStaysOpen: true) { _ = try manager.update(slug: slug, name: nil, tint: tint, logo: nil) }
    }
    public func changeLogo(_ slug: String, to url: URL?) async {
        let manager = self.manager
        if let old = accounts.first(where: { $0.id == slug })?.identity.logoPath { logos[old] = nil }
        await change(slug, "Updating the photo of \(name(of: slug))…", touchesApp: true, primaryStaysOpen: true) { _ = try manager.update(slug: slug, name: nil, tint: nil, logo: url) }
    }
    public func changeNote(_ slug: String, to note: String) async {
        let manager = self.manager
        await change(slug, "Saving…", touchesApp: true, primaryStaysOpen: true) { _ = try manager.update(slug: slug, name: nil, tint: nil, logo: nil, note: note) }
    }

    // MARK: Repair, command line

    /// Repair: reattach every account, re-create the command line link if it's missing.
    public func repair() {
        do {
            let state = try store.load()
            for identity in state.identities { try manager.attachBrain(to: identity, state: state) }
            try linkCommandLineForHooks()
            message = UserMessage(title: "All set", detail: "Every account is attached to the memory again.")
        } catch { present(error) }
        reload()
        // Reattaching writes the hooks too: Settings, which shows them, reads them again.
        if hooks != nil { Task { await refreshHooks() } }
    }

    /// The hooks call ~/.local/bin/brainmerge: the link is set up at the end of onboarding, never over a valid link.
    public func linkCommandLineForHooks() throws {
        if let cli = commandLine() { try CLIInstaller.ensureLink(paths: paths, target: cli) }
    }

    /// Reads what Settings says about the hooks, on the core queue (the settings files may sit behind links). Nothing in a
    /// capture or a demo, whose demo home's hooks call nothing real.
    public func refreshHooks() async {
        guard !AppLifecycle.isCaptureOrDemo(environment: environment) else { hooks = nil; return }
        let manager = self.manager, queue = coreQueue
        hooks = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: HooksSummary.read(manager)) }
        }
    }

    /// "Repair hooks": every account's hooks written as they are today, the person's own hooks left as they are, then the
    /// link they call (made, or pointed at this copy when what it pointed at is gone; a link that works is kept).
    public func repairHooks() async {
        let manager = self.manager, paths = self.paths, cli = commandLine()
        _ = await perform("Repairing hooks…") {
            try manager.repairHooks()
            if let cli { try CLIInstaller.ensureLink(paths: paths, target: cli) }
        }
        await refreshHooks()
    }

    public func installCommandLine() {
        guard let cli = commandLine() else {
            message = UserMessage(title: "Command line not available", detail: "This build of Brainmerge doesn't embed the command line. Open the app from the Brainmerge release to get it.")
            return
        }
        do {
            try CLIInstaller.ensureLink(paths: paths, target: cli, replaceValid: true)
            message = UserMessage(title: "Command line ready", detail: "You can run brainmerge in a terminal. Make sure ~/.local/bin is in your PATH.")
        } catch { present(error) }
    }

    public var commandLineInstalled: Bool {
        let link = CLIInstaller.link(in: paths)
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return FileManager.default.fileExists(atPath: dest)
    }

    public func present(_ error: Error) { message = Self.sentence(for: error) }

    /// Clears a message once its caller showed it elsewhere (the edit sheet), only if it is still the one shown.
    public func dismiss(_ shown: UserMessage) { if message?.id == shown.id { message = nil } }

    /// What a click on an account in the sidebar does (see SidebarAccountAction). A Claude Code only account: open()
    /// says why there is no window.
    public func perform(_ action: SidebarAccountAction, on slug: String) async {
        switch action {
        case .rebuild: await rebuild(slug)
        case .opening, .updating: break
        case .open, .show, .none: open(slug)
        }
    }

    /// The minute clock: new projects get their memory link, the emails are read again, and the usage too while the
    /// window is open. With the window closed, no transcript is read in the background: the usage is only on screen.
    /// Returns the usage read it started, if any.
    @discardableResult
    public func onProjectsTick() -> Task<Void, Never>? {
        wireNewProjects()
        refreshCodeAccounts()
        guard windowOpen else { return nil }
        return Task { await refreshUsage() }
    }

    /// Back in front: a login may have changed in Claude Code, and Claude may have updated itself meanwhile.
    public func windowBecameActive() {
        guard launchPhase == .ready else { return }
        refreshCodeAccounts()
        if !needsOnboarding { Task { await checkClaudeUpdate() } }
    }

    // MARK: Uninstall

    /// What removing Brainmerge would take away and what it leaves, for the confirmation.
    public func uninstallPlan() -> Uninstaller.Plan? {
        try? Uninstaller(paths: paths, store: store, manager: manager).plan()
    }

    /// Removes everything Brainmerge set up; memories and logins stay. Nil, with a message, when an account is still open.
    /// The clocks stay stopped until it is over (the window may close meanwhile), and for good once it is done: the app
    /// then goes to the Trash and quits.
    public func uninstall() async -> Uninstaller.Report? {
        if let open = openAccounts.first(where: { !$0.identity.isPrimary }), let sentence = runningSentence(open.id) { message = sentence; return nil }
        let uninstaller = Uninstaller(paths: paths, store: store, manager: manager)
        watchingSuspended = true
        stopWatching()
        let report: Uninstaller.Report? = await perform("Removing Brainmerge…") { try uninstaller.run() }
        if report == nil { watchingSuspended = false; updateWatching() }
        return report
    }

    /// Whether this copy should offer to move itself, injectable in tests.
    @ObservationIgnored var offersMove: @MainActor () -> Bool = { Installer.shouldOfferMove() && !Installer.wasDeclined() }
    private var moveOffered = false

    /// At launch from a disk image or Downloads: offer to install into Applications, once per process (the window
    /// now closes and opens again while Brainmerge keeps running).
    public func offerMoveIfNeeded() {
        guard !moveOffered, offersMove() else { return }
        moveOffered = true
        message = UserMessage(title: "Move Brainmerge to Applications?",
                              detail: "Brainmerge works best from your Applications folder: the command line and the Dock icons point there. It will copy itself there and open again.",
                              action: .moveToApplications, actionLabel: "Move and open")
    }

    // MARK: Monitoring

    /// Starts every clock and checks Claude once; asking again while they run changes nothing.
    public func startWatching() { watch(Set(Watchers.Clock.allCases)) }
    public func stopWatching() { watch([]) }

    /// The clocks the window and the menu bar icon need now (see Watchers.plan). Only once a window was tracked and the
    /// first load is done; never during an uninstall.
    public func updateWatching() {
        guard tracksWindow, !watchingSuspended, launchPhase == .ready else { return }
        watch(Watchers.plan(windowOpen: windowOpen, iconShown: showsMenuBarIcon, needsOnboarding: needsOnboarding))
    }

    /// A Bool rather than a count of appearances, which could drift: there is one main window.
    public func windowAppeared() { tracksWindow = true; windowOpen = true; updateWatching() }
    public func windowDisappeared() { windowOpen = false; updateWatching() }

    /// Restarts the clocks only when the set changes, and checks Claude once when they start from none.
    private func watch(_ clocks: Set<Watchers.Clock>) {
        guard clocks != watchedClocks else { return }
        let starting = watchedClocks.isEmpty
        watchedClocks = clocks
        guard !clocks.isEmpty else { watchers.stop(); return }
        watchers.start(clocks, running: { [weak self] in self?.reload() },
                       memory: { [weak self] in self?.refreshMemory() },
                       projects: { [weak self] in self?.onProjectsTick() },
                       claude: { [weak self] in Task { await self?.checkClaudeUpdate() } })
        if starting { Task { await checkClaudeUpdate() } }
    }

    /// Projects that appeared since the last pass get their memory link, in each account's memory (idempotent, without a message).
    func wireNewProjects() {
        guard let state = try? store.load() else { return }
        for identity in state.identities {
            guard let folder = state.brain(for: identity) else { continue }
            let brain = Brain(root: folder.url)
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists, brain.isInitialized else { continue }
            let wiring = MemoryWiring(brain: brain, paths: paths, machineID: state.machineID, knownRoots: state.brains.map(\.url))
            // Under the memory's lock, like the SessionStart hook writing the same list of projects: taken at once or this
            // turn is skipped (the main thread never waits), and the next minute links what is left.
            _ = try? BrainGit(brain: brain).withLock(timeout: 0) { try wiring.wire(profile: profile, identitySlug: identity.slug) }
        }
    }

    /// One check at a time: the launch and the window coming to the front can both ask, a copy is never rebuilt twice at once.
    private var checkingClaudeUpdate = false

    /// An account whose app is being worked on (an update, a rename, a swap, a removal) is left alone: its change
    /// rebuilds it anyway. Each account is looked at again when its turn comes, as an earlier step may have changed it.
    /// A failure is said once per Claude version, so the same failure never comes back every few minutes.
    public func checkClaudeUpdate() async {
        reload()
        guard let claude, !checkingClaudeUpdate else { return }
        checkingClaudeUpdate = true
        defer { checkingClaudeUpdate = false }
        let manager = self.manager
        for slug in accounts.map(\.id) {
            guard !accountsBusy.contains(slug), let account = accounts.first(where: { $0.id == slug }),
                  UpdatePolicy.shouldRebuild(identity: account.identity, installedVersion: claude.version, running: account.isRunning, autoRebuild: autoRebuild)
            else { continue }
            rebuilding.insert(slug)
            defer { rebuilding.remove(slug) }
            let key = "\(slug)@\(claude.version)"
            if case .failure(let error) = await outcome("Updating \(account.identity.name) for Claude \(claude.version)…", { try manager.rebuild(slug: slug) }),
               !reportedRebuildFailures.contains(key) {
                reportedRebuildFailures.insert(key)
                present(error)
            }
        }
    }

    @discardableResult
    public func setNotesApp(_ setting: String?) -> Task<Void, Never> {
        if notesApp != setting { notesApp = setting }
        return save(.notesApp) { $0.notesApp = setting }
    }

    // MARK: The graph's source

    /// What the graph shows: the chosen vault unless its folder was gone when last looked at (an external disk may come
    /// back), else the selected memory. Read on every redraw, so it never touches the disk itself.
    public var graphTarget: GraphTarget {
        if let path = graphVault, !graphVaultGone {
            return GraphTarget(root: URL(fileURLWithPath: path, isDirectory: true), style: .vault)
        }
        return GraphTarget(root: selectedBrain?.root, style: .memory)
    }

    public var graphSource: GraphSource {
        if graphTarget.style == .vault, let path = graphVault { return .vault(path) }
        return .memory(selectedFolder?.id ?? "")
    }

    /// Looks at a vault's folder: gone, or a vault. For a vault in Documents, iCloud Drive or another guarded place,
    /// macOS may hold the look until the person answers its consent prompt: always called off the main thread, so the
    /// window never freezes meanwhile. Injectable in tests.
    @ObservationIgnored var isVaultGone: @Sendable (URL) -> Bool = { ObsidianVaults.isGone($0) }
    @ObservationIgnored var isVaultFolder: @Sendable (URL) -> Bool = { ObsidianVaults.isVault($0) }
    /// Bumped by every pick of the graph's source: a look at a vault's folder that ends after a later pick changes nothing.
    private var graphPicks = 0

    /// Reads Obsidian's list of vaults again (paths only), and looks whether the chosen vault's folder is still there,
    /// off the main thread. Called when the graph shows. A vault in a place macOS guards is only looked at once picked.
    public func refreshVaults() async {
        let paths = self.paths, chosen = graphVault, isGone = isVaultGone
        let (vaults, gone) = await Task.detached(priority: .userInitiated) {
            (ObsidianVaults.known(paths: paths), chosen.map { isGone(URL(fileURLWithPath: $0, isDirectory: true)) } ?? false)
        }.value
        if vaults != obsidianVaults { obsidianVaults = vaults }
        // Another vault picked meanwhile was looked at when picked.
        guard chosen == graphVault, gone != graphVaultGone else { return }
        graphVaultGone = gone
    }

    /// Shows a memory (which the whole screen then shows) or a vault in the graph. The task ends once the choice is saved.
    @discardableResult
    public func selectGraphSource(_ source: GraphSource) -> Task<Void, Never> {
        graphPicks += 1
        switch source {
        case .memory(let id):
            let memory = selectBrain(id), vault = setGraphVault(nil)
            return Task { await memory.value; await vault.value }
        case .vault(let path):
            let url = URL(fileURLWithPath: path, isDirectory: true)
            // Obsidian's list can hold a vault moved or deleted since: a guarded one was listed without a look.
            return pickVault(path, looking: isVaultGone, at: url) { [weak self] in
                self?.message = UserMessage(title: "Vault not found",
                                            detail: "Obsidian lists \(url.lastPathComponent), but its folder is not there any more. Open it in Obsidian, or choose it again.")
            }
        }
    }

    /// A folder picked by hand: shown when Obsidian keeps a vault in it, explained when not. The task ends once the
    /// choice is saved, or refused.
    @discardableResult
    public func chooseVault(_ url: URL) -> Task<Void, Never> {
        graphPicks += 1
        let isVault = isVaultFolder
        return pickVault(url.standardizedFileURL.path, looking: { !isVault($0) }, at: url) { [weak self] in
            self?.message = UserMessage(title: "Not an Obsidian vault",
                                        detail: "Pick a folder you open in Obsidian as a vault. Obsidian keeps its settings there, in a hidden .obsidian folder.")
        }
    }

    /// Looks at the folder off the main thread (`refused` says whether it may not be shown), then shows it, or says why
    /// not, unless the person picked something else meanwhile.
    private func pickVault(_ path: String, looking refused: @escaping @Sendable (URL) -> Bool, at url: URL,
                           otherwise explain: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let pick = graphPicks
        return Task {
            let refuse = await Task.detached(priority: .userInitiated) { refused(url) }.value
            guard pick == graphPicks else { return }
            if refuse { explain(); return }
            await setGraphVault(path).value
        }
    }

    /// Like every setting: the choice moves at once, the file is saved on the core queue after the work already there.
    @discardableResult
    func setGraphVault(_ path: String?) -> Task<Void, Never> {
        if graphVault != path { graphVault = path }
        // Only called with a folder just seen, or with none.
        if graphVaultGone { graphVaultGone = false }
        return save(.graphVault) { $0.graphVault = path }
    }

    /// Shows or hides the menu bar icon. The switch moves at once and is saved like every setting (see `save`).
    @discardableResult
    public func setMenuBarIcon(_ on: Bool) -> Task<Void, Never> {
        if menuBarIcon != on { menuBarIcon = on }
        updateWatching()
        return save(.menuBarIcon) { $0.menuBarIcon = on }
    }

    /// Saves one setting on the core queue, after any work already there, which saves the same file (a rebuild records
    /// its Claude version): a save from the main thread meanwhile would be undone by the state that work read before.
    /// The value on screen has already moved; the task ends once it is saved.
    func save(_ setting: Setting, _ change: @escaping @Sendable (inout AppState) -> Void) -> Task<Void, Never> {
        pendingSaves[setting, default: 0] += 1
        let store = self.store, begins = saveBegins
        // Queued now, not when the task first runs on the main actor: saves keep their order and a busy main actor
        // cannot delay them. The task only waits for the end.
        let saved = DispatchGroup()
        saved.enter()
        coreQueue.async {
            begins()
            // Under the state lock: the command line's own change in the meantime is kept, not overwritten.
            try? store.update { change(&$0) }
            saved.leave()
        }
        return Task {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                // Sendable: an inferred main actor closure would trap when the group calls it off the main thread.
                saved.notify(queue: .global(qos: .userInitiated)) { @Sendable in done.resume() }
            }
            pendingSaves[setting, default: 1] -= 1
        }
    }

    /// The icon was dragged out of the menu bar: the switch turns off. True when the window must open again, as nothing
    /// else would be left to click. SwiftUI can echo a removal after the app hid the icon itself (the splash, the guide,
    /// a capture): that must not turn the setting off for good, and changes nothing.
    public func menuBarIconRemoved() -> Bool {
        guard showsMenuBarIcon else { return false }
        setMenuBarIcon(false)
        return AppLifecycle.reopensWindow(afterIconRemovedWith: windowOpen)
    }

    /// Waits for the core work in progress to end, at most `limit`. True when none is left.
    public func waitForWork(limit: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while working != nil {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    @discardableResult
    public func setAutoRebuild(_ on: Bool) -> Task<Void, Never> {
        if autoRebuild != on { autoRebuild = on }
        return save(.autoRebuild) { $0.autoRebuild = on }
    }

    /// The language for the brain's next notes (BRAIN.md of a new folder); existing notes do not change.
    @discardableResult
    public func setLanguage(_ language: BrainLanguage) -> Task<Void, Never> {
        if self.language != language { self.language = language }
        return save(.language) { $0.brainLanguage = language }
    }

    // MARK: Sentences

    /// The "X is open" sentence with the account's real name, when it is running.
    func runningSentence(_ slug: String) -> UserMessage? {
        guard let account = accounts.first(where: { $0.id == slug }), account.isRunning else { return nil }
        let name = account.identity.name
        return UserMessage(title: "\(name) is open", detail: "Quit \(name) first, then try again.", action: .quit(slug: slug), actionLabel: "Quit \(name)")
    }

    /// Every error becomes a sentence that says what to do.
    public static func sentence(for error: Error) -> UserMessage {
        guard let e = error as? BrainmergeError else {
            return UserMessage(title: "Something went wrong", detail: "\(error.localizedDescription) Try again, or open Settings to repair.")
        }
        switch e {
        case .claudeAppNotFound:
            return UserMessage(title: "Claude isn't installed", detail: "Get Claude from claude.ai/download, install it, then open Brainmerge again.", action: .getClaude, actionLabel: "Get Claude")
        case .identityRunning(let slug):
            let name = slug.capitalized
            return UserMessage(title: "\(name) is open", detail: "Quit \(name) first, then try again.", action: .quit(slug: slug), actionLabel: "Quit \(name)")
        case .identityNameTaken(let name):
            return UserMessage(title: "Name already used", detail: "There is already an account called \(name). Pick another name.")
        case .brainNotConfigured, .brainNotFound:
            return UserMessage(title: "Choose where the memory lives first", detail: "Open Settings and pick a folder for the memory.", action: .openSettings, actionLabel: "Open Settings")
        case .lockTimeout:
            // The memory's lock and the list of accounts' lock alike: the hooks and the command line save too.
            return UserMessage(title: "Busy saving", detail: "Another Brainmerge process is saving. Try again in a few seconds.")
        case .gitUnavailable:
            // The detail stands alone: the new memory sheet shows it without the button.
            return UserMessage(title: "History needs git",
                               detail: "Brainmerge keeps each memory's history with git, which comes with Apple's Command Line Tools. Install Apple's tools, then try again.",
                               action: .installAppleTools, actionLabel: "Install Apple's tools")
        case .profileMissing(let path):
            return UserMessage(title: "Claude Code setup not found", detail: "Expected a folder at \(path). Open Claude once, then try again.")
        case .cliOnReadOnlyVolume:
            return UserMessage(title: "Move Brainmerge to Applications first", detail: "Brainmerge is running from a disk image or a read-only disk. Drag it to your Applications folder, open it from there, then try again.")
        case .cliLinkOccupied(let path):
            return UserMessage(title: "Something else lives at ~/.local/bin/brainmerge", detail: "Move or rename \(path), then try again.")
        case .brainInUse(let name):
            return UserMessage(title: "This memory is still in use", detail: "An account still writes to \(name). Attach it to another memory first, then forget this one.")
        case .brainIsDefault:
            return UserMessage(title: "The shared memory stays", detail: "The default memory cannot be forgotten. Attach accounts to other memories if you want them apart.")
        case .brainUnknown:
            return UserMessage(title: "That memory is gone", detail: "It is no longer in the list. Pick another one.")
        case .brainNameTaken(let name):
            return UserMessage(title: "Name already used", detail: "There is already a memory called \(name). Pick another name.")
        case .nameInvalid:
            return UserMessage(title: "Give it a name", detail: "One line, up to \(NameRules.maxLength) characters.")
        case .claudeAppTampered:
            return UserMessage(title: "Claude's signature is broken", detail: "The Claude app on this Mac does not match its own signature, so Brainmerge will not copy it. Reinstall Claude from claude.ai/download, then try again.", action: .getClaude, actionLabel: "Get Claude")
        default:
            return UserMessage(title: "Something went wrong", detail: "\(e.description)")
        }
    }
}
