import Foundation

/// Adopts, adds, updates, removes, rebuilds, and launches identities. Never handles a credential:
/// each account signs itself into the official Claude instance.
public final class IdentityManager: @unchecked Sendable {
    public let paths: Paths
    public let store: StateStore
    public let launcherBinary: URL
    public let cliPath: String
    public let claudeAppURL: URL
    public let shell: Shell
    public let monitor: ProcessMonitor
    /// false in tests: disposable bundles aren't registered with Launch Services.
    public let registerLaunchers: Bool
    /// How long attaching an account waits for the memory's lock (a save or a session start holding it) before it
    /// says "Busy saving"; shorter in tests.
    public var memoryLockTimeout: TimeInterval = 5

    public init(paths: Paths, store: StateStore, launcherBinary: URL, cliPath: String,
                claudeAppURL: URL = ClaudeApp.defaultURL(), shell: Shell = Shell(), registerLaunchers: Bool = true,
                monitor: ProcessMonitor? = nil) {
        self.paths = paths; self.store = store; self.launcherBinary = launcherBinary
        self.cliPath = cliPath; self.claudeAppURL = claudeAppURL; self.shell = shell
        self.monitor = monitor ?? ProcessMonitor(shell: shell); self.registerLaunchers = registerLaunchers
    }

    public struct AddRequest: Sendable {
        public var name: String
        public var tint: Tint = .blue
        public var logo: URL? = nil
        public var note: String? = nil
        public var surfaces = Surfaces()
        public var iconMode: IconMode = .launcher
        public var sharedHistory = false
        public var adoptCLIProfile: URL? = nil
        public var adoptDesktopData: URL? = nil
        /// An existing memory (its id) for this account; nil is the default one.
        public var brain: String? = nil
        /// Create a memory of its own, named after the account, in `~/Brain-<slug>`.
        public var ownBrain = false
        public init(name: String) { self.name = name }
    }

    // MARK: Identities

    @discardableResult
    public func adoptPrimary(name: String) throws -> Identity {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        if let existing = state.primary { return existing }
        guard FileManager.default.fileExists(atPath: paths.primaryCLIProfile.path) else {
            throw BrainmergeError.profileMissing(paths.primaryCLIProfile.path)
        }
        let name = NameRules.clean(name)
        guard !name.isEmpty else { throw BrainmergeError.nameInvalid }
        try ensureNameAvailable(name, excluding: nil, in: state)
        let identity = Identity(slug: IdentitySlug.make(from: name, taken: state.takenSlugs), name: name,
                                tint: .orange, isPrimary: true)
        let registryBefore = registrySnapshot(for: identity, in: state)
        do {
            try attachBrain(to: identity, state: state)
            state.identities.append(identity)
            try store.save(state)
        } catch {
            undoAttach(identity, state: state, registryBefore: registryBefore, created: [])
            throw error
        }
        return identity
    }

    @discardableResult
    public func add(_ request: AddRequest) throws -> Identity {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        _ = try configuredBrain(state)
        let name = NameRules.clean(request.name)
        guard !name.isEmpty else { throw BrainmergeError.nameInvalid }
        try ensureNameAvailable(name, excluding: nil, in: state)
        if let id = request.brain, state.brain(id: id) == nil { throw BrainmergeError.brainUnknown(id) }
        let claude = try ClaudeApp.detect(at: claudeAppURL)
        var identity = Identity(slug: IdentitySlug.make(from: name, taken: slugsInUse(state)),
                                name: name, tint: request.tint, logoPath: request.logo?.path, note: request.note.map(NameRules.clean),
                                surfaces: request.surfaces, iconMode: request.iconMode,
                                sharedHistory: request.sharedHistory,
                                cliProfilePath: request.adoptCLIProfile?.path,
                                desktopDataPath: request.adoptDesktopData?.path,
                                brain: request.brain)
        if identity.sharedHistory {
            guard !request.ownBrain else { throw BrainmergeError.sharedHistoryNeedsSameMemory }
            var candidate = state
            candidate.identities.append(identity)
            try ensureSharedHistoryMemory(candidate)
        }
        if request.ownBrain {
            identity.brain = try addBrain(name: name, path: nil, language: state.brainLanguage, in: &state).id
        }

        // Everything written from here on is undone when a later step fails: an account that is not saved keeps no hook,
        // no block, no list of notes and no folder Brainmerge made for it.
        let fm = FileManager.default
        let created = [identity.cliProfile(in: paths), identity.desktopData(in: paths)].filter { !fm.fileExists(atPath: $0.path) }
        let registryBefore = registrySnapshot(for: identity, in: state)
        do {
            // The CLI profile also serves the Desktop app's Code tab: it always exists.
            let primaryProfile = CLIProfile(directory: state.primary?.cliProfile(in: paths) ?? paths.primaryCLIProfile)
            let profile = try CLIProfile.create(at: identity.cliProfile(in: paths),
                                                inheritingFrom: primaryProfile.exists ? primaryProfile : nil)
            if identity.sharedHistory { try shareHistory(of: profile, with: primaryProfile) }
            try attachBrain(to: identity, state: state)

            if identity.surfaces.desktop {
                try fm.createDirectory(at: identity.desktopData(in: paths), withIntermediateDirectories: true)
                try buildApp(for: identity, claude: claude)
                identity.builtForClaudeVersion = claude.version
            }
            state.identities.append(identity)
            try store.save(state)
        } catch {
            undoAttach(identity, state: state, registryBefore: registryBefore, created: created)
            for app in apps(of: identity) where fm.fileExists(atPath: app.path) { try? fm.removeItem(at: app) }
            throw error
        }
        // Added from the app or with `brainmerge identity add`: its terminal command, where the brainmerge link points.
        if state.terminalCommands {
            _ = try? CLIInstaller.linkAccount(paths: paths, slug: identity.slug, target: URL(fileURLWithPath: cliPath))
        }
        return identity
    }

    /// Renames, changes the tint, the logo, the note or the kind of Dock icon. The slug never changes: it carries
    /// the attribution and the folders. Switching the icon mode replaces the launcher by a tinted copy, or the reverse.
    /// The primary can be changed while Claude runs: nothing of Claude is rebuilt, only files written atomically, and its
    /// own app (`ownApp`, the primary only) is built, renamed or removed next to Claude. It never gets a tinted copy.
    @discardableResult
    public func update(slug: String, name: String?, tint: Tint?, logo: URL?, note: String? = nil, iconMode: IconMode? = nil,
                       clearLogo: Bool = false, ownApp: Bool? = nil) throws -> Identity {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard var identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        let name = name.map(NameRules.clean)
        if let name {
            guard !name.isEmpty else { throw BrainmergeError.nameInvalid }
            try ensureNameAvailable(name, excluding: slug, in: state)
        }
        if identity.isPrimary, iconMode == .tintedClone { throw BrainmergeError.primaryIsClaude }
        try ensureEditable(identity)
        let before = identity
        if let name { identity.name = name }
        if let tint { identity.tint = tint }
        if let logo { identity.logoPath = logo.path }
        if clearLogo { identity.logoPath = nil }
        if let note { identity.note = NameRules.clean(note) }
        if let iconMode { identity.iconMode = iconMode }
        if let ownApp, identity.isPrimary { identity.ownApp = ownApp }
        return try commit([(before, identity)], in: &state)[0]
    }

    /// Swaps the names of two accounts in one operation, for names that ended up on each other's account. Both apps are
    /// built under their new names first (the old ones set aside meanwhile), then both names are written at once: no
    /// temporary name ever reaches the state, Claude's instructions or the memory, and a failure changes nothing.
    /// Swapping an account with itself does nothing.
    public func swapNames(_ slug: String, with otherSlug: String) throws {
        guard slug != otherSlug else { return }
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard let one = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        guard let other = state.identity(slug: otherSlug) else { throw BrainmergeError.identityNotFound(otherSlug) }
        try ensureEditable(one)
        try ensureEditable(other)
        var newOne = one, newOther = other
        newOne.name = other.name
        newOther.name = one.name
        _ = try commit([(one, newOne), (other, newOther)], in: &state)
    }

    /// Applies changes to accounts in the order that keeps them usable whatever fails: the new apps are built while the
    /// old ones are set aside, then Claude's instructions, the memory's list of accounts and the state are written with the
    /// final values, and only then are the old apps deleted. On a failure, the old apps are put back, the unchanged
    /// accounts are attached again, and the error is thrown.
    @discardableResult
    func commit(_ changes: [(before: Identity, after: Identity)], in state: inout AppState) throws -> [Identity] {
        let replacement = try replaceApps(changes)
        var updated = changes.map(\.after)
        if let version = replacement.claude?.version {
            for index in updated.indices where replacement.rebuilt.contains(updated[index].slug) && !updated[index].isPrimary {
                updated[index].builtForClaudeVersion = version
            }
        }
        var next = state
        next.identities = next.identities.map { identity in updated.first { $0.slug == identity.slug } ?? identity }
        do {
            for identity in updated { try attachBrain(to: identity, state: next) }
            try store.save(next)
        } catch {
            replacement.restore()
            for change in changes { try? attachBrain(to: change.before, state: state) }
            throw error
        }
        replacement.discard()
        state = next
        return updated
    }

    /// Old apps moved out of the way while the new ones are built: put back on a failure, deleted once the change is saved.
    struct AppReplacement {
        var claude: ClaudeApp?
        /// Accounts whose app was built.
        var rebuilt: Set<String> = []
        var setAside: [(original: URL, parked: URL)] = []
        var built: [URL] = []
        var folder: URL?

        func restore() {
            let fm = FileManager.default
            for url in built where fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
            for app in setAside.reversed() where !fm.fileExists(atPath: app.original.path) { try? fm.moveItem(at: app.parked, to: app.original) }
            if let folder { try? fm.removeItem(at: folder) }
        }

        func discard() {
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Sets aside the apps each change replaces, then builds the new ones; a failure puts everything back as it was.
    /// A secondary with a Claude window always gets its app built again (it carries the name, color and photo). The
    /// primary's own app only when what it shows changed, or it is missing; switched off, it goes.
    func replaceApps(_ changes: [(before: Identity, after: Identity)]) throws -> AppReplacement {
        let fm = FileManager.default
        var plan: [(old: [URL], build: Identity?)] = []
        for (before, after) in changes {
            if after.isPrimary {
                guard let app = after.appURL(in: paths) else { plan.append((apps(of: before), nil)); continue }
                let looksTheSame = before.appURL(in: paths) == app && before.tint == after.tint && before.logoPath == after.logoPath
                if looksTheSame, fm.fileExists(atPath: app.path) { continue }
                plan.append((apps(of: before), after))
            } else if after.surfaces.desktop {
                plan.append((apps(of: before), after))
            }
        }
        var replacement = AppReplacement()
        if plan.contains(where: { $0.build != nil }) { replacement.claude = try ClaudeApp.detect(at: claudeAppURL) }
        do {
            for old in plan.flatMap(\.old) where fm.fileExists(atPath: old.path) {
                let folder = try replacement.folder ?? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: old, create: true)
                replacement.folder = folder
                let parked = folder.appending(path: "\(replacement.setAside.count)-\(old.lastPathComponent)", directoryHint: .isDirectory)
                try fm.moveItem(at: old, to: parked)
                replacement.setAside.append((old, parked))
            }
            if let claude = replacement.claude {
                for identity in plan.compactMap(\.build) {
                    if let url = identity.appURL(in: paths) { replacement.built.append(url) }
                    try buildApp(for: identity, claude: claude)
                    replacement.rebuilt.insert(identity.slug)
                }
            }
        } catch {
            replacement.restore()
            throw error
        }
        return replacement
    }

    public func remove(slug: String, deleteData: Bool) throws {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard let identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        let fm = FileManager.default
        if !identity.isPrimary { try ensureStopped(identity) }
        try detachBrain(from: identity)
        for app in apps(of: identity) where fm.fileExists(atPath: app.path) {
            // Out of Launch Services first: its record would outlive the bundle.
            if registerLaunchers { _ = try? shell.run(LauncherBuilder.lsregister, ["-u", app.path]) }
            try fm.removeItem(at: app)
        }
        if !identity.isPrimary {
            // Only folders created by Brainmerge can be deleted; an adopted folder doesn't belong to it.
            if deleteData {
                var owned: [URL] = []
                if identity.desktopDataPath == nil { owned.append(identity.desktopData(in: paths)) }
                if identity.cliProfilePath == nil { owned.append(identity.cliProfile(in: paths)) }
                for dir in owned where fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            }
        }
        state.identities.removeAll { $0.slug == slug }
        try store.save(state)
        CLIInstaller.unlinkAccount(paths: paths, slug: slug)
        // Its lists of notes written and not saved go too, in every memory: they would keep those notes out of your own
        // edits' save for good.
        for folder in state.brains {
            let ledger = TouchedLedger(brain: Brain(root: folder.url), slug: slug)
            for list in [ledger.file, ledger.sending] { try? fm.removeItem(at: list) }
        }
    }

    /// Rebuilds a secondary's app for the installed Claude (the account must be closed), or the primary's own app when it
    /// has one (Claude may stay open: the primary's app only opens it).
    public func rebuild(slug: String) throws {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard var identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        if identity.isPrimary {
            guard identity.appURL(in: paths) != nil else { return }
            try buildApp(for: identity, claude: try ClaudeApp.detect(at: claudeAppURL))
            return
        }
        guard identity.surfaces.desktop else { return }
        try ensureStopped(identity)
        let claude = try ClaudeApp.detect(at: claudeAppURL)
        try buildApp(for: identity, claude: claude)
        identity.builtForClaudeVersion = claude.version
        state.identities = state.identities.map { $0.slug == slug ? identity : $0 }
        try store.save(state)
    }

    public func launch(slug: String) throws {
        let state = try store.load()
        guard let identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        let claude = try ClaudeApp.detect(at: claudeAppURL)
        let target: URL
        if identity.isPrimary {
            target = claude.url
        } else {
            target = identity.iconMode == .launcher
                ? paths.launcherApp(name: identity.bundleDisplayName)
                : paths.tintedClone(name: identity.bundleDisplayName)
        }
        try shell.check("/usr/bin/open", [target.path])
    }

    public func isRunning(_ identity: Identity) throws -> Bool {
        try monitor.isRunning(identity: identity, paths: paths, claude: try ClaudeApp.detect(at: claudeAppURL))
    }

    public func quit(_ identity: Identity) throws {
        try monitor.quit(identity: identity, paths: paths, claude: try ClaudeApp.detect(at: claudeAppURL))
    }

    // MARK: Memories

    /// Creates a memory: a Brain folder (`~/Brain-<id>` unless a path is given) and its entry in the state.
    @discardableResult
    public func addBrain(name: String, path: URL?, language: BrainLanguage) throws -> MemoryFolder {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        let folder = try addBrain(name: name, path: path, language: language, in: &state)
        try store.save(state)
        return folder
    }

    func addBrain(name: String, path: URL?, language: BrainLanguage, in state: inout AppState) throws -> MemoryFolder {
        let clean = NameRules.clean(name)
        if clean.isEmpty { throw BrainmergeError.brainNameEmpty }
        if let taken = state.brains.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            throw BrainmergeError.brainNameTaken(taken.name)
        }
        let id = IdentitySlug.make(from: clean, taken: state.takenBrainIDs)
        let root = (path ?? paths.home.appending(path: "Brain-\(id)", directoryHint: .isDirectory)).standardizedFileURL
        if state.brains.contains(where: { $0.url.standardizedFileURL.path == root.path }) { throw BrainmergeError.brainFolderInUse(root.path) }
        let brain = try Brain.initialize(at: root, language: language)
        let folder = MemoryFolder(id: id, name: clean, path: brain.root.path)
        state.brains.append(folder)
        return folder
    }

    /// "Choose memory folder" for a memory whose folder is gone: the folder it lives in now (the person moved it), or an
    /// empty one where it starts again (only what is missing is created, like `Brain.initialize`). Its accounts are
    /// attached to it there; no note is moved. With no memory at all, the folder becomes the default memory. A folder
    /// another memory uses, or one inside another git repository, is refused before anything changes.
    @discardableResult
    public func relocateBrain(id: String, to folder: URL, language: BrainLanguage) throws -> MemoryFolder {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        let index = state.brains.firstIndex { $0.id == id }
        guard index != nil || (state.brains.isEmpty && id == AppState.defaultBrainID) else { throw BrainmergeError.brainUnknown(id) }
        let root = folder.standardizedFileURL
        if state.brains.contains(where: { $0.id != id && $0.url.standardizedFileURL.path == root.path }) { throw BrainmergeError.brainFolderInUse(root.path) }
        let brain = try Brain.initialize(at: root, language: language)
        if let index { state.brains[index].path = brain.root.path } else { state.brainPath = brain.root.path }
        try store.save(state)
        // Every account of this memory follows it; one that cannot (its Claude Code folder is gone) does not stop the others.
        var firstError: Error?
        for identity in state.identities(using: id) {
            do { try attachBrain(to: identity, state: state) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
        guard let saved = state.brain(id: id) else { throw BrainmergeError.brainUnknown(id) }
        return saved
    }

    /// Forgets a memory: its entry goes, its folder stays. Never the default one, never one an account still uses.
    public func forgetBrain(id: String) throws {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard let folder = state.brain(id: id) else { throw BrainmergeError.brainUnknown(id) }
        if state.defaultBrain?.id == id { throw BrainmergeError.brainIsDefault }
        if !state.identities(using: id).isEmpty { throw BrainmergeError.brainInUse(folder.name) }
        state.brains.removeAll { $0.id == id }
        try store.save(state)
    }

    /// Renames a memory: its display name only, never its folder.
    public func renameBrain(id: String, name: String) throws {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard let index = state.brains.firstIndex(where: { $0.id == id }) else { throw BrainmergeError.brainUnknown(id) }
        let clean = NameRules.clean(name)
        if clean.isEmpty { throw BrainmergeError.brainNameEmpty }
        if let taken = state.brains.first(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            throw BrainmergeError.brainNameTaken(taken.name)
        }
        state.brains[index].name = clean
        try store.save(state)
    }

    /// Attaches an account to another memory: the managed block and the memory links move, the notes do not.
    public func setBrain(of slug: String, to id: String) throws {
        let held = try store.lock()
        defer { held.release() }
        var state = try store.load()
        guard var identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        guard state.brain(id: id) != nil else { throw BrainmergeError.brainUnknown(id) }
        identity.brain = id
        var next = state
        next.identities = next.identities.map { $0.slug == slug ? identity : $0 }
        try ensureSharedHistoryMemory(next)
        try ensureStopped(identity)
        try attachBrain(to: identity, state: state)
        state.identities = state.identities.map { $0.slug == slug ? identity : $0 }
        try store.save(state)
    }

    // MARK: Brain

    /// Managed block, hooks (Stop, SessionStart, PostToolUse), memory links, identity registry, in the identity's memory,
    /// whose .gitignore is brought up to date. Idempotent. Under the memory's lock, like the SessionStart hook and the
    /// saves that read the same lists: a lock still held after `memoryLockTimeout` fails with `.lockTimeout` ("Busy
    /// saving") before anything is written.
    public func attachBrain(to identity: Identity, state: AppState) throws {
        let brain = try memory(for: identity, in: state)
        let profile = CLIProfile(directory: identity.cliProfile(in: paths))
        guard profile.exists else { throw BrainmergeError.profileMissing(profile.directory.path) }
        try BrainGit(brain: brain).withLock(timeout: memoryLockTimeout) {
            let claudeMD = profile.claudeMD.resolvingSymlinksInPath()
            // A CLAUDE.md that is not UTF-8 is the person's text all the same: never replaced by the block alone.
            var existing = ""
            if FileManager.default.fileExists(atPath: claudeMD.path) {
                guard let text = try? String(contentsOf: claudeMD, encoding: .utf8) else {
                    throw BrainmergeError.unreadableText(profile.claudeMD.path)
                }
                existing = text
            }
            try brain.ensureIgnores()
            let block = ManagedBlock.render(identityName: identity.name, slug: identity.slug, brainPath: brain.root.path)
            try Data(ManagedBlock.upsert(in: existing, block: block).utf8).write(to: claudeMD, options: .atomic)
            try HookInstaller.installAll(settingsFile: profile.settingsFile, cliPath: cliPath, slug: identity.slug)
            _ = try MemoryWiring(brain: brain, paths: paths, machineID: state.machineID, knownRoots: state.brains.map(\.url))
                .wire(profile: profile, identitySlug: identity.slug)
            var registry = try IdentityRegistry.load(brain.identitiesFile)
            let before = registry
            registry.record(identity)
            try registry.save(to: brain.identitiesFile)
            // The account's entry in the memory's list of accounts: its save carries it, like its list of projects.
            if registry != before { try? TouchedLedger(brain: brain, slug: identity.slug).append(".brainmerge/identities.json") }
        }
    }

    /// Each account's hooks as they stand, for the accounts whose Claude Code folder exists, in the accounts' order.
    public func hooksHealth() throws -> [(Identity, HookInstaller.Health)] {
        try store.load().identities.compactMap { identity in
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists else { return nil }
            return (identity, HookInstaller.health(settingsFile: profile.settingsFile, cliPath: cliPath, slug: identity.slug))
        }
    }

    /// Writes every account's hooks as they are today (see HookInstaller.install), and nothing else. An account whose
    /// Claude Code folder is gone is skipped: it is never recreated here. One that cannot be written (its settings.json
    /// is not JSON) stops only itself: the others are still repaired, then the first error is thrown.
    public func repairHooks() throws {
        var failure: Error?
        for identity in try store.load().identities {
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists else { continue }
            do { try HookInstaller.installAll(settingsFile: profile.settingsFile, cliPath: cliPath, slug: identity.slug) }
            catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Undoes what attaching an account that was never saved wrote: its hooks and block (only when there, so a file
    /// Brainmerge did not change is not rewritten), its lists of notes, the memory's list of accounts as it was, and the
    /// folders made for it. The notes it brought stay in the memory: nothing is lost.
    func undoAttach(_ identity: Identity, state: AppState, registryBefore: Data?, created: [URL]) {
        let fm = FileManager.default
        let profile = CLIProfile(directory: identity.cliProfile(in: paths))
        if (try? HookInstaller.isInstalled(settingsFile: profile.settingsFile)) == true {
            try? HookInstaller.remove(settingsFile: profile.settingsFile)
        }
        let claudeMD = profile.claudeMD.resolvingSymlinksInPath()
        if let content = try? String(contentsOf: claudeMD, encoding: .utf8), ManagedBlock.contains(content) {
            try? Data(ManagedBlock.remove(from: content).utf8).write(to: claudeMD, options: .atomic)
        }
        if let brain = try? memory(for: identity, in: state) {
            let ledger = TouchedLedger(brain: brain, slug: identity.slug)
            for list in [ledger.file, ledger.sending] { try? fm.removeItem(at: list) }
            // Empty: there was none. nil: it could not be read, so it is left as it is.
            if let registryBefore, registryBefore.isEmpty { try? fm.removeItem(at: brain.identitiesFile) }
            else if let registryBefore { try? registryBefore.write(to: brain.identitiesFile, options: .atomic) }
        }
        for folder in created { try? fm.removeItem(at: folder) }
    }

    /// The memory's list of accounts before an attach, for `undoAttach`: empty when there is none, nil when unreadable.
    func registrySnapshot(for identity: Identity, in state: AppState) -> Data? {
        guard let file = (try? memory(for: identity, in: state))?.identitiesFile else { return nil }
        return FileManager.default.fileExists(atPath: file.path) ? try? Data(contentsOf: file) : Data()
    }

    /// Removes the block and every Brainmerge hook. The memory links stay: they break nothing and the brain keeps everything.
    public func detachBrain(from identity: Identity) throws {
        let profile = CLIProfile(directory: identity.cliProfile(in: paths))
        let claudeMD = profile.claudeMD.resolvingSymlinksInPath()
        if let content = try? String(contentsOf: claudeMD, encoding: .utf8) {
            try Data(ManagedBlock.remove(from: content).utf8).write(to: claudeMD, options: .atomic)
        }
        if FileManager.default.fileExists(atPath: profile.settingsFile.path) {
            try HookInstaller.remove(settingsFile: profile.settingsFile)
        }
    }

    // MARK: Internals

    /// The slugs a new account may not take: the accounts', and those whose Claude Code or Claude app folder is already
    /// there (left by a removed account and still signed in, or made by hand). A new account never takes over a folder it
    /// did not create, so deleting an account's data only ever deletes what Brainmerge made.
    func slugsInUse(_ state: AppState) -> Set<String> {
        let fm = FileManager.default
        func leftovers(in folder: URL, prefix: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() }
                .filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        let support = paths.desktopData(slug: "x", isPrimary: false).deletingLastPathComponent()
        return state.takenSlugs.union(leftovers(in: paths.home, prefix: ".claude-")).union(leftovers(in: support, prefix: "claude-"))
    }

    /// An account with a shared conversation history uses the first account's memory: both wire the same project links,
    /// which would otherwise go back and forth between two memories.
    func ensureSharedHistoryMemory(_ state: AppState) throws {
        let first = state.primary.flatMap { state.brain(for: $0)?.id } ?? state.defaultBrain?.id
        if state.identities.contains(where: { $0.sharedHistory && !$0.isPrimary && state.brain(for: $0)?.id != first }) {
            throw BrainmergeError.sharedHistoryNeedsSameMemory
        }
    }

    /// Two identities never share a name: the name forms the launcher app's path.
    func ensureNameAvailable(_ name: String, excluding slug: String?, in state: AppState) throws {
        let candidate = Identity(slug: "candidate", name: name).bundleDisplayName
        let taken = state.identities.contains {
            $0.slug != slug && $0.bundleDisplayName.caseInsensitiveCompare(candidate) == .orderedSame
        }
        if taken { throw BrainmergeError.identityNameTaken(name) }
    }

    /// What `update` requires of an account before changing it, checked the same way by `swapNames` before its first step.
    /// A secondary is closed first (its app is rebuilt). The primary may stay open: Claude itself is never rebuilt, and the
    /// files an edit writes (CLAUDE.md, settings, the memory's list of accounts) are replaced atomically.
    func ensureEditable(_ identity: Identity) throws {
        if !identity.isPrimary { try ensureStopped(identity) }
    }

    /// Rebuilding, updating, or removing a running identity would break its instance.
    func ensureStopped(_ identity: Identity) throws {
        if try isRunning(identity) { throw BrainmergeError.identityRunning(identity.slug) }
    }

    func configuredBrain(_ state: AppState) throws -> Brain {
        guard let url = state.brainURL else { throw BrainmergeError.brainNotConfigured }
        let brain = Brain(root: url)
        guard brain.isInitialized else { throw BrainmergeError.brainNotFound(brain.root.path) }
        return brain
    }

    /// The identity's memory, initialized.
    func memory(for identity: Identity, in state: AppState) throws -> Brain {
        guard let folder = state.brain(for: identity) else { throw BrainmergeError.brainNotConfigured }
        let brain = Brain(root: folder.url)
        guard brain.isInitialized else { throw BrainmergeError.brainNotFound(brain.root.path) }
        return brain
    }

    /// Every app Brainmerge may have built for this account, for removal: both kinds for a secondary, the own app of the primary.
    func apps(of identity: Identity) -> [URL] {
        if identity.isPrimary { return identity.appURL(in: paths).map { [$0] } ?? [] }
        return [paths.launcherApp(name: identity.bundleDisplayName), paths.tintedClone(name: identity.bundleDisplayName)]
    }

    /// The primary only ever gets its own app, which opens Claude: never a tinted copy, whatever the state says.
    func buildApp(for identity: Identity, claude: ClaudeApp) throws {
        let icon = try makeIcon(for: identity, claude: claude)
        if identity.isPrimary {
            try LauncherBuilder(paths: paths, launcherBinary: launcherBinary, shell: shell)
                .buildOpener(for: identity, claude: claude, icon: icon, register: registerLaunchers)
            return
        }
        switch identity.iconMode {
        case .launcher:
            try LauncherBuilder(paths: paths, launcherBinary: launcherBinary, shell: shell)
                .build(for: identity, claude: claude, icon: icon, register: registerLaunchers)
        case .tintedClone:
            try TintedCloneBuilder(paths: paths, launcherBinary: launcherBinary, shell: shell)
                .build(for: identity, claude: claude, icon: icon, register: registerLaunchers)
        }
    }

    /// The identity's icon, kept in Application Support/Brainmerge/icons/<slug>.icns. A photo that is gone keeps the icon
    /// made from it, or the tinted one when there is none.
    func makeIcon(for identity: Identity, claude: ClaudeApp) throws -> URL {
        try FileManager.default.createDirectory(at: paths.iconsDir, withIntermediateDirectories: true)
        let output = paths.iconsDir.appending(path: "\(identity.slug).icns")
        if let logo = identity.logoPath, FileManager.default.fileExists(atPath: logo) {
            try IconGenerator.icns(fromImage: URL(fileURLWithPath: logo), output: output, shell: shell)
        } else if identity.logoPath != nil, FileManager.default.fileExists(atPath: output.path) {
            // The photo was moved or deleted: the icon already made from it stays, and a change never fails for it.
        } else {
            try IconGenerator.tintedICNS(from: claude.icon, tint: identity.tint, output: output, shell: shell)
        }
        return output
    }

    /// Shared history: the profile's `projects` becomes a link to the primary's,
    /// only if it's missing or empty. A real, non-empty folder is never touched.
    func shareHistory(of profile: CLIProfile, with primary: CLIProfile) throws {
        let fm = FileManager.default
        let dir = profile.projectsDir
        if let attributes = try? fm.attributesOfItem(atPath: dir.path) {
            if (attributes[.type] as? FileAttributeType) == .typeSymbolicLink { return }
            guard try fm.contentsOfDirectory(atPath: dir.path).isEmpty else { return }
            try fm.removeItem(at: dir)
        }
        try fm.createDirectory(at: primary.projectsDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: dir, withDestinationURL: primary.projectsDir)
    }
}
