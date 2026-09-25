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

/// Whether the window still shows the launch splash (the first load is running) or its screens.
public enum LaunchPhase: Equatable, Sendable { case loading, ready }

public struct UserMessage: Identifiable, Equatable, Sendable {
    /// What a message's button does: typed, so it never depends on a label.
    public enum Action: Equatable, Sendable { case quit(slug: String), quitOthersThenOpen(slug: String), getClaude, openSettings, moveToApplications }
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
    public private(set) var accounts: [Account] = []
    /// The default memory (the first of the list), initialized.
    public private(set) var brain: Brain?
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
    public var message: UserMessage?
    /// Accounts launched and not seen running yet: cleared as soon as `reload()` sees their process,
    /// or after a few seconds if it never shows up.
    public private(set) var opening: Set<String> = []
    private var openingMarks: [String: Int] = [:]
    /// Accounts whose app bundle is being rebuilt, updated or removed right now: opening one would open a half-built app.
    /// Kept apart from `rebuilding`, whose marker must outlive the nested rebuild of an update.
    public private(set) var busy: Set<String> = []
    private var busyCount: [String: Int] = [:]
    /// A waiting sentence while heavy core work runs off the main thread.
    public private(set) var working: String?
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
    /// The Mac's memory pressure, injectable in tests.
    public var memoryPressure: @Sendable () -> MemoryPressure.Level = { MemoryPressure.current() ?? .normal }
    public private(set) var totalResidentBytes: Int64 = 0
    /// Resident memory per open account (instance and child processes). Kept apart from the accounts and compared
    /// at a 16 MB step: a few kilobytes moving with every `ps` do not redraw the interface.
    public private(set) var memoryBySlug: [String: Int64] = [:]
    /// A sentence when the Mac is low on memory, nil otherwise.
    public private(set) var memoryWarning: String?
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
    /// Where apps the person made are looked for: ~/Applications, and /Applications for the real home only.
    public var appFolders: [URL]
    private let watchers = Watchers()
    /// The clocks run: several windows, the launch and the onboarding switch can all ask, the clocks start once.
    public private(set) var isWatching = false

    /// `.loading` from the process start until the first load is done: the window shows the splash meanwhile.
    public private(set) var launchPhase: LaunchPhase = .loading
    private var launchTask: Task<Void, Never>?
    private var beforeReady: [@MainActor () -> Void] = []
    /// Read off the main thread by the first load, then used once by `reload()` and `refreshMemory()`.
    private var prefetchedSnapshot: ProcessMonitor.Snapshot?
    private var prefetchedLog: (root: URL, entries: [BrainGit.Entry])?

    public init(paths: Paths, store: StateStore, manager: IdentityManager, claudeAppURL: URL) {
        self.paths = paths; self.store = store; self.manager = manager; self.claudeAppURL = claudeAppURL
        appFolders = ExistingApps.folders(for: paths)
    }

    /// The installed app's model: engine embedded in the bundle. The command line link is only set up
    /// at the end of onboarding or from settings, never at launch.
    public static func live() -> AppModel {
        let paths = Paths.current()
        let launcher = Bundle.main.url(forAuxiliaryExecutable: "launcher") ?? LauncherBuilder.siblingLauncher()
        let manager = IdentityManager(paths: paths, store: StateStore(paths: paths), launcherBinary: launcher,
                                      cliPath: CLIInstaller.link(in: paths).path, claudeAppURL: ClaudeApp.defaultURL())
        let model = AppModel(paths: paths, store: StateStore(paths: paths), manager: manager, claudeAppURL: ClaudeApp.defaultURL())
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
    static func skipsSplash(environment: [String: String]) -> Bool {
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
    private func loadFirstTime() async {
        let monitor = manager.monitor, store = self.store
        let (snapshot, log) = await Task.detached(priority: .userInitiated) { () -> (ProcessMonitor.Snapshot, (root: URL, entries: [BrainGit.Entry])?) in
            let snapshot = (try? monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
            let brain = (try? store.load())?.brainURL.map(Brain.init(root:)).flatMap { $0.isInitialized ? $0 : nil }
            return (snapshot, brain.map { (root: $0.root, entries: (try? BrainGit(brain: $0).log(limit: 200)) ?? []) })
        }.value
        prefetchedSnapshot = snapshot
        prefetchedLog = log
        reload()
        prefetchedSnapshot = nil
        prefetchedLog = nil
    }

    /// The command line embedded in the app (task 8), looked up by its exact name.
    static var embeddedCLI: URL? {
        let exe = CLIInstaller.currentExecutable() ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return CLIInstaller.embeddedCLI(besideExecutable: exe)
    }

    public var needsOnboarding: Bool { brain == nil || accounts.first(where: { $0.identity.isPrimary }) == nil }
    public var openAccounts: [Account] { accounts.filter(\.isRunning) }

    /// Reloads the state and the running instances: a single `ps` for every account. Only writes a property if
    /// its value changes, so as not to redraw the whole interface on every clock tick. Returns true if something changed.
    @discardableResult
    public func reload() -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
            if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value; changed = true }
        }
        set(\.claude, try? ClaudeApp.detect(at: claudeAppURL))
        guard let state = try? store.load() else { set(\.accounts, []); set(\.brain, nil); return changed }
        set(\.language, state.brainLanguage)
        set(\.autoRebuild, state.autoRebuild)
        set(\.notesApp, state.notesApp)
        set(\.brains, state.brains)
        set(\.brain, state.brainURL.map(Brain.init(root:)).flatMap { $0.isInitialized ? $0 : nil })
        if let selected = selectedBrainID, state.brain(id: selected) == nil { selectedBrainID = state.defaultBrain?.id }
        else if selectedBrainID == nil, let first = state.defaultBrain { selectedBrainID = first.id }
        let snapshot = prefetchedSnapshot ?? (try? manager.monitor.snapshot()) ?? ProcessMonitor.Snapshot(mains: [], all: [])
        let claudeApp = claude
        var memory: [String: Int64] = [:]
        codeAccountsRead.formIntersection(state.identities.map(\.slug))
        readCodeAccounts(of: state.identities.filter { !codeAccountsRead.contains($0.slug) })
        set(\.accounts, state.identities.map { identity in
            let main = claudeApp.flatMap { app in snapshot.mains.first { ProcessMonitor.matches($0, identity: identity, paths: paths, claude: app) } }
            if let main { memory[identity.slug] = snapshot.residentBytes(of: main.pid) }
            let session = identity.surfaces.desktop && DesktopSession.hasSession(dataDir: identity.desktopData(in: paths))
            return Account(identity: identity, isRunning: main != nil, hasSession: session, claudeVersion: Self.versionState(of: identity, claude: claudeApp),
                           codeAccount: codeAccounts[identity.slug])
        })
        let step: Int64 = 16 * 1024 * 1024
        func coarse(_ m: [String: Int64]) -> [String: Int64] { m.mapValues { ($0 + step / 2) / step } }
        if coarse(memory) != coarse(memoryBySlug) {
            memoryBySlug = memory
            totalResidentBytes = memory.values.reduce(0, +)
            changed = true
        }
        set(\.memoryWarning, Self.memoryWarning(level: memoryPressure(), open: openAccounts.count, bytes: totalResidentBytes))
        // A window that showed up is no longer "opening".
        set(\.opening, opening.subtracting(openAccounts.map(\.id)))
        return changed
    }

    public func residentBytes(of slug: String) -> Int64 { memoryBySlug[slug] ?? 0 }

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
    public func apply(_ edit: AccountEdit, to slug: String) async {
        guard let account = accounts.first(where: { $0.id == slug }) else { return }
        if let problem = edit.validate(existing: accounts.map(\.identity).filter { $0.slug != slug }) {
            message = UserMessage(title: "Check the form", detail: problem); return
        }
        let identity = account.identity
        let name = edit.trimmedName == identity.name ? nil : edit.trimmedName
        let tint = edit.tint == identity.tint ? nil : edit.tint
        let logo = edit.logo?.path == identity.logoPath ? nil : edit.logo
        let clearLogo = edit.logo == nil && identity.logoPath != nil
        let note = edit.trimmedNote == (identity.note ?? "") ? nil : edit.trimmedNote
        let iconMode: IconMode? = identity.isPrimary || edit.distinctIcon == (identity.iconMode == .tintedClone) ? nil : (edit.distinctIcon ? .tintedClone : .launcher)
        let ownApp: Bool? = identity.isPrimary && edit.ownApp != (identity.ownApp == true) ? edit.ownApp : nil
        if let old = identity.logoPath, logo != nil || clearLogo { logos[old] = nil }
        if name != nil || tint != nil || logo != nil || clearLogo || note != nil || iconMode != nil || ownApp != nil {
            let manager = self.manager
            await change(slug, "Saving \(edit.trimmedName)…", touchesApp: true, primaryStaysOpen: true) {
                _ = try manager.update(slug: slug, name: name, tint: tint, logo: logo, note: note, iconMode: iconMode, clearLogo: clearLogo, ownApp: ownApp)
            }
            if message != nil { return }
        }
        if brain(of: identity)?.id != edit.memory {
            await setBrain(of: slug, to: edit.memory)
        }
    }

    // MARK: Live updates of the tinted copies

    /// The accounts whose copy is being rebuilt right now: the automatic check leaves them alone.
    var rebuilding: Set<String> = []

    /// Every account whose app is being worked on, whatever the reason: the sidebar does not offer to open them.
    var accountsBusy: Set<String> { busy.union(rebuilding) }

    /// Quits the account if it is open, rebuilds its copy for the installed Claude, then reopens it.
    public func updateAccount(_ slug: String) async {
        guard let account = accounts.first(where: { $0.id == slug }), !rebuilding.contains(slug) else { return }
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
        await rebuild(slug)
        if wasRunning, message == nil { open(slug) }
    }

    public func updateAll() async {
        for slug in outdatedAccounts.map(\.id) { await updateAccount(slug) }
    }

    /// "The Mac is low on memory": a sentence, not an alarm, only when the kernel says so and accounts are open.
    static func memoryWarning(level: MemoryPressure.Level, open: Int, bytes: Int64) -> String? {
        guard level >= .warning, open > 0 else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
        let accounts = open == 1 ? "1 open account uses" : "\(open) open accounts use"
        let severity = level == .critical ? "Your Mac is very low on memory." : "Your Mac is running low on memory."
        return "\(severity) \(accounts) \(size). Close the ones you don't use."
    }

    /// The memory shown on the Memory screen: the selected one when it exists and is initialized, else the default one.
    public var selectedBrain: Brain? {
        guard let id = selectedBrainID, let folder = brains.first(where: { $0.id == id }) else { return brain }
        let candidate = Brain(root: folder.url)
        return candidate.isInitialized ? candidate : brain
    }
    public var selectedFolder: MemoryFolder? { brains.first { $0.id == selectedBrainID } ?? brains.first }
    public func selectBrain(_ id: String?) { selectedBrainID = id ?? brains.first?.id }
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
    public func setBrain(of slug: String, to id: String) async {
        let manager = self.manager
        let target = brains.first { $0.id == id }?.name ?? id
        await change(slug, "Attaching \(name(of: slug)) to \(target)…") { try manager.setBrain(of: slug, to: id) }
        refreshMemory()
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

    /// Marks an account as opening until its window runs; the timer is only a fallback for a launch that never shows up.
    public func markOpening(_ slug: String) {
        opening.insert(slug)
        let mark = (openingMarks[slug] ?? 0) + 1
        openingMarks[slug] = mark
        Task {
            try? await Task.sleep(for: .seconds(4))
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
        do { try manager.launch(slug: slug); markOpening(slug) } catch { present(error) }
        reload()
    }

    /// This account's Claude process, if it's running.
    func runningProcess(for slug: String) -> Int32? {
        guard let account = accounts.first(where: { $0.id == slug }), account.isRunning, let claude else { return nil }
        let processes = (try? manager.monitor.claudeProcesses()) ?? []
        return processes.first { ProcessMonitor.matches($0, identity: account.identity, paths: paths, claude: claude) }?.pid
    }

    func show(_ pid: Int32) {
        lastShownProcess = pid
        if let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
            app.activate()
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

    /// Launchers, tinted copies, deletions: run separately, with a waiting sentence; nil and a message on failure.
    func perform<T: Sendable>(_ label: String, _ work: @escaping @Sendable () throws -> T) async -> T? {
        working = label
        defer { working = nil }
        let outcome = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
        switch outcome {
        case .success(let value): reload(); return value
        case .failure(let error): present(error); reload(); return nil
        }
    }

    /// Any change to an open account is refused, with its real name, before calling the engine.
    /// `touchesApp`: the work deletes and rebuilds (or removes) the account's app, so the account is busy meanwhile.
    /// Only a secondary account with a Claude window opens through its own app: the primary opens Claude itself.
    /// `primaryStaysOpen`: the work never touches Claude (names, colors, notes, the primary's own app), so an open
    /// primary is changed as it is, without asking to quit it.
    func change(_ slug: String, _ label: String, touchesApp: Bool = false, primaryStaysOpen: Bool = false,
                _ work: @escaping @Sendable () throws -> Void) async {
        let identity = accounts.first { $0.id == slug }?.identity
        let mayStayOpen = primaryStaysOpen && identity?.isPrimary == true
        if !mayStayOpen, let open = runningSentence(slug) { message = open; return }
        let marks = touchesApp && identity.map { !$0.isPrimary && $0.surfaces.desktop } == true
        if marks { markBusy(slug, true) }
        defer { if marks { markBusy(slug, false) } }
        _ = await perform(label, work)
    }

    /// Counted, so that two overlapping changes of one account do not clear each other's mark.
    private func markBusy(_ slug: String, _ on: Bool) {
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

    public func rebuild(_ slug: String) async {
        let manager = self.manager
        await change(slug, "Rebuilding \(name(of: slug))…", touchesApp: true, primaryStaysOpen: true) { try manager.rebuild(slug: slug) }
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
    public func swapNames(_ slug: String, with other: String) async {
        guard let one = accounts.first(where: { $0.id == slug }), let two = accounts.first(where: { $0.id == other }), slug != other else { return }
        for account in [one, two] where !account.identity.isPrimary {
            if let open = runningSentence(account.id) { message = open; return }
        }
        let marked = [one, two].filter { !$0.identity.isPrimary && $0.identity.surfaces.desktop }.map(\.id)
        for id in marked { markBusy(id, true) }
        defer { for id in marked { markBusy(id, false) } }
        let manager = self.manager
        _ = await perform("Swapping the names of \(one.identity.name) and \(two.identity.name)…") { try manager.swapNames(slug, with: other) }
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
    }

    /// The Stop hook calls ~/.local/bin/brainmerge: the link is set up at the end of onboarding, never over a valid link.
    public func linkCommandLineForHooks() throws {
        if let cli = Self.embeddedCLI { try CLIInstaller.ensureLink(paths: paths, target: cli) }
    }

    public func installCommandLine() {
        guard let cli = Self.embeddedCLI else {
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

    // MARK: Uninstall

    /// What removing Brainmerge would take away and what it leaves, for the confirmation.
    public func uninstallPlan() -> Uninstaller.Plan? {
        try? Uninstaller(paths: paths, store: store, manager: manager).plan()
    }

    /// Removes everything Brainmerge set up; memories and logins stay. Nil, with a message, when an account is still open.
    public func uninstall() async -> Uninstaller.Report? {
        if let open = openAccounts.first(where: { !$0.identity.isPrimary }), let sentence = runningSentence(open.id) { message = sentence; return nil }
        let uninstaller = Uninstaller(paths: paths, store: store, manager: manager)
        stopWatching()
        let report: Uninstaller.Report? = await perform("Removing Brainmerge…") { try uninstaller.run() }
        if report == nil { startWatching() }
        return report
    }

    /// At launch from a disk image or Downloads: offer to install into Applications.
    public func offerMoveIfNeeded() {
        guard Installer.shouldOfferMove(), !Installer.wasDeclined() else { return }
        message = UserMessage(title: "Move Brainmerge to Applications?",
                              detail: "Brainmerge works best from your Applications folder: the command line and the Dock icons point there. It will copy itself there and open again.",
                              action: .moveToApplications, actionLabel: "Move and open")
    }

    // MARK: Monitoring

    /// Starts the clocks and checks Claude once; asking again while they run changes nothing.
    public func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        watchers.start(running: { [weak self] in self?.reload() },
                       memory: { [weak self] in self?.refreshMemory() },
                       projects: { [weak self] in self?.wireNewProjects(); self?.refreshCodeAccounts(); Task { await self?.refreshUsage() } },
                       claude: { [weak self] in Task { await self?.checkClaudeUpdate() } })
        Task { await checkClaudeUpdate() }
    }
    public func stopWatching() { isWatching = false; watchers.stop() }

    /// Projects that appeared since the last pass get their memory link, in each account's memory (idempotent, without a message).
    func wireNewProjects() {
        guard let state = try? store.load() else { return }
        for identity in state.identities {
            guard let folder = state.brain(for: identity) else { continue }
            let brain = Brain(root: folder.url)
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists, brain.isInitialized else { continue }
            _ = try? MemoryWiring(brain: brain, paths: paths, machineID: state.machineID, knownRoots: state.brains.map(\.url))
                .wire(profile: profile, identitySlug: identity.slug)
        }
    }

    /// One check at a time: the launch and the window coming to the front can both ask, a copy is never rebuilt twice at once.
    private var checkingClaudeUpdate = false

    public func checkClaudeUpdate() async {
        reload()
        guard let claude, !checkingClaudeUpdate else { return }
        checkingClaudeUpdate = true
        defer { checkingClaudeUpdate = false }
        let manager = self.manager
        for account in accounts where !rebuilding.contains(account.id) && UpdatePolicy.shouldRebuild(identity: account.identity, installedVersion: claude.version, running: account.isRunning, autoRebuild: autoRebuild) {
            let slug = account.id
            rebuilding.insert(slug)
            defer { rebuilding.remove(slug) }
            let key = "\(slug)@\(claude.version)"
            let alreadyReported = reportedRebuildFailures.contains(key)
            let before = message
            if alreadyReported { message = nil }
            let done: Void? = await perform("Updating \(account.identity.name) for Claude \(claude.version)…") { try manager.rebuild(slug: slug) }
            if done == nil {
                if alreadyReported { message = before } else { reportedRebuildFailures.insert(key) }
            }
        }
    }

    public func setNotesApp(_ setting: String?) {
        guard var state = try? store.load() else { return }
        state.notesApp = setting
        try? store.save(state)
        reload()
    }

    public func setAutoRebuild(_ on: Bool) {
        guard var state = try? store.load() else { return }
        state.autoRebuild = on
        try? store.save(state)
        reload()
    }

    /// The language for the brain's next notes (BRAIN.md of a new folder); existing notes do not change.
    public func setLanguage(_ language: BrainLanguage) {
        guard var state = try? store.load() else { return }
        state.brainLanguage = language
        try? store.save(state)
        reload()
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
            return UserMessage(title: "The memory is busy", detail: "Another account is saving right now. Try again in a few seconds.")
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
