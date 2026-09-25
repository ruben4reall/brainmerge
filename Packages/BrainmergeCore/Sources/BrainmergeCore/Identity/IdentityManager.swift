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
        var state = try store.load()
        if let existing = state.primary { return existing }
        guard FileManager.default.fileExists(atPath: paths.primaryCLIProfile.path) else {
            throw BrainmergeError.profileMissing(paths.primaryCLIProfile.path)
        }
        let identity = Identity(slug: IdentitySlug.make(from: name, taken: state.takenSlugs), name: name,
                                tint: .orange, isPrimary: true)
        try attachBrain(to: identity, state: state)
        state.identities.append(identity)
        try store.save(state)
        return identity
    }

    @discardableResult
    public func add(_ request: AddRequest) throws -> Identity {
        var state = try store.load()
        _ = try configuredBrain(state)
        let name = NameRules.clean(request.name)
        guard !name.isEmpty else { throw BrainmergeError.nameInvalid }
        try ensureNameAvailable(name, excluding: nil, in: state)
        if let id = request.brain, state.brain(id: id) == nil { throw BrainmergeError.brainUnknown(id) }
        let claude = try ClaudeApp.detect(at: claudeAppURL)
        var identity = Identity(slug: IdentitySlug.make(from: name, taken: state.takenSlugs),
                                name: name, tint: request.tint, logoPath: request.logo?.path, note: request.note.map(NameRules.clean),
                                surfaces: request.surfaces, iconMode: request.iconMode,
                                sharedHistory: request.sharedHistory,
                                cliProfilePath: request.adoptCLIProfile?.path,
                                desktopDataPath: request.adoptDesktopData?.path,
                                brain: request.brain)
        if request.ownBrain {
            identity.brain = try addBrain(name: name, path: nil, language: state.brainLanguage, in: &state).id
        }

        // The CLI profile also serves the Desktop app's Code tab: it always exists.
        let primaryProfile = CLIProfile(directory: state.primary?.cliProfile(in: paths) ?? paths.primaryCLIProfile)
        let profile = try CLIProfile.create(at: identity.cliProfile(in: paths),
                                            inheritingFrom: primaryProfile.exists ? primaryProfile : nil)
        if identity.sharedHistory { try shareHistory(of: profile, with: primaryProfile) }
        try attachBrain(to: identity, state: state)

        if identity.surfaces.desktop {
            try FileManager.default.createDirectory(at: identity.desktopData(in: paths), withIntermediateDirectories: true)
            try buildApp(for: identity, claude: claude)
            identity.builtForClaudeVersion = claude.version
        }
        state.identities.append(identity)
        try store.save(state)
        return identity
    }

    /// Renames, changes the tint, the logo, the note or the kind of Dock icon. The slug never changes: it carries
    /// the attribution and the folders. Switching the icon mode replaces the launcher by a tinted copy, or the reverse.
    /// The primary can be changed while Claude runs: nothing of Claude is rebuilt, only files written atomically, and its
    /// own app (`ownApp`, the primary only) is built, renamed or removed next to Claude. It never gets a tinted copy.
    @discardableResult
    public func update(slug: String, name: String?, tint: Tint?, logo: URL?, note: String? = nil, iconMode: IconMode? = nil,
                       clearLogo: Bool = false, ownApp: Bool? = nil) throws -> Identity {
        var state = try store.load()
        guard var identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        let name = name.map(NameRules.clean)
        if let name {
            guard !name.isEmpty else { throw BrainmergeError.nameInvalid }
            try ensureNameAvailable(name, excluding: slug, in: state)
        }
        if identity.isPrimary, iconMode == .tintedClone { throw BrainmergeError.primaryIsClaude }
        try ensureEditable(identity)
        let fm = FileManager.default
        let before = identity
        let oldName = identity.bundleDisplayName
        if let name { identity.name = name }
        if let tint { identity.tint = tint }
        if let logo { identity.logoPath = logo.path }
        if clearLogo { identity.logoPath = nil }
        if let note { identity.note = NameRules.clean(note) }
        if let iconMode { identity.iconMode = iconMode }
        if let ownApp, identity.isPrimary { identity.ownApp = ownApp }
        try attachBrain(to: identity, state: state)
        if identity.isPrimary {
            try updateOwnApp(from: before, to: identity)
        } else if identity.surfaces.desktop {
            for app in [paths.launcherApp(name: oldName), paths.tintedClone(name: oldName)] where fm.fileExists(atPath: app.path) {
                try fm.removeItem(at: app)
            }
            let claude = try ClaudeApp.detect(at: claudeAppURL)
            try buildApp(for: identity, claude: claude)
            identity.builtForClaudeVersion = claude.version
        }
        state.identities = state.identities.map { $0.slug == slug ? identity : $0 }
        try store.save(state)
        return identity
    }

    /// Swaps the names of two accounts in one operation, for names that ended up on each other's account. It goes
    /// through a temporary name, so neither rename meets the other's name and no app is built over the other's.
    /// Everything a rename needs is checked first (both accounts, both stopped, Claude installed when an app is rebuilt);
    /// if a later step still fails, the first rename is undone. Swapping an account with itself does nothing.
    public func swapNames(_ slug: String, with otherSlug: String) throws {
        guard slug != otherSlug else { return }
        let state = try store.load()
        guard let one = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        guard let other = state.identity(slug: otherSlug) else { throw BrainmergeError.identityNotFound(otherSlug) }
        try ensureEditable(one)
        try ensureEditable(other)
        let rebuildsApp = { (identity: Identity) in identity.appURL(in: self.paths) != nil }
        if rebuildsApp(one) || rebuildsApp(other) { _ = try ClaudeApp.detect(at: claudeAppURL) }
        // The account without an app of its own takes the temporary name: nothing is built under it.
        let (first, second) = rebuildsApp(one) && !rebuildsApp(other) ? (other, one) : (one, other)
        var temporary = "Swapping names"
        var n = 2
        while state.identities.contains(where: { $0.bundleDisplayName.caseInsensitiveCompare(temporary) == .orderedSame })
                || FileManager.default.fileExists(atPath: paths.launcherApp(name: temporary).path)
                || FileManager.default.fileExists(atPath: paths.tintedClone(name: temporary).path) {
            temporary = "Swapping names \(n)"; n += 1
        }
        try update(slug: first.slug, name: temporary, tint: nil, logo: nil)
        do {
            try update(slug: second.slug, name: first.name, tint: nil, logo: nil)
        } catch {
            _ = try? update(slug: first.slug, name: first.name, tint: nil, logo: nil)
            throw error
        }
        try update(slug: first.slug, name: second.name, tint: nil, logo: nil)
    }

    public func remove(slug: String, deleteData: Bool) throws {
        var state = try store.load()
        guard let identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        let fm = FileManager.default
        if !identity.isPrimary { try ensureStopped(identity) }
        try detachBrain(from: identity)
        for app in apps(of: identity) where fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
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
    }

    /// Rebuilds a secondary's app for the installed Claude (the account must be closed), or the primary's own app when it
    /// has one (Claude may stay open: the primary's app only opens it).
    public func rebuild(slug: String) throws {
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

    /// Forgets a memory: its entry goes, its folder stays. Never the default one, never one an account still uses.
    public func forgetBrain(id: String) throws {
        var state = try store.load()
        guard let folder = state.brain(id: id) else { throw BrainmergeError.brainUnknown(id) }
        if state.defaultBrain?.id == id { throw BrainmergeError.brainIsDefault }
        if !state.identities(using: id).isEmpty { throw BrainmergeError.brainInUse(folder.name) }
        state.brains.removeAll { $0.id == id }
        try store.save(state)
    }

    /// Renames a memory: its display name only, never its folder.
    public func renameBrain(id: String, name: String) throws {
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
        var state = try store.load()
        guard var identity = state.identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        guard state.brain(id: id) != nil else { throw BrainmergeError.brainUnknown(id) }
        try ensureStopped(identity)
        identity.brain = id
        try attachBrain(to: identity, state: state)
        state.identities = state.identities.map { $0.slug == slug ? identity : $0 }
        try store.save(state)
    }

    // MARK: Brain

    /// Managed block, Stop hook, memory links, identity registry, in the identity's memory. Idempotent.
    public func attachBrain(to identity: Identity, state: AppState) throws {
        let brain = try memory(for: identity, in: state)
        let profile = CLIProfile(directory: identity.cliProfile(in: paths))
        guard profile.exists else { throw BrainmergeError.profileMissing(profile.directory.path) }
        let claudeMD = profile.claudeMD.resolvingSymlinksInPath()
        let existing = (try? String(contentsOf: claudeMD, encoding: .utf8)) ?? ""
        let block = ManagedBlock.render(identityName: identity.name, slug: identity.slug, brainPath: brain.root.path)
        try Data(ManagedBlock.upsert(in: existing, block: block).utf8).write(to: claudeMD, options: .atomic)
        try HookInstaller.install(settingsFile: profile.settingsFile,
                                  command: HookInstaller.syncCommand(cliPath: cliPath, slug: identity.slug))
        _ = try MemoryWiring(brain: brain, paths: paths, machineID: state.machineID, knownRoots: state.brains.map(\.url))
            .wire(profile: profile, identitySlug: identity.slug)
        var registry = try IdentityRegistry.load(brain.identitiesFile)
        registry.record(identity)
        try registry.save(to: brain.identitiesFile)
    }

    /// Removes the block and the hook. The memory links stay: they break nothing and the brain keeps everything.
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

    /// The primary's own app follows its name, color and photo, and goes when switched off. It is only rebuilt when what it
    /// shows changed (or it went missing), so a note or an unrelated edit never needs the Claude app.
    func updateOwnApp(from before: Identity, to identity: Identity) throws {
        let fm = FileManager.default
        guard let app = identity.appURL(in: paths) else {
            for old in apps(of: before) where fm.fileExists(atPath: old.path) { try fm.removeItem(at: old) }
            return
        }
        let looksTheSame = before.appURL(in: paths) == app && before.tint == identity.tint && before.logoPath == identity.logoPath
        if looksTheSame, fm.fileExists(atPath: app.path) { return }
        let claude = try ClaudeApp.detect(at: claudeAppURL)
        for old in apps(of: before) where fm.fileExists(atPath: old.path) { try fm.removeItem(at: old) }
        try buildApp(for: identity, claude: claude)
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

    /// The identity's icon, kept in Application Support/Brainmerge/icons/<slug>.icns.
    func makeIcon(for identity: Identity, claude: ClaudeApp) throws -> URL {
        try FileManager.default.createDirectory(at: paths.iconsDir, withIntermediateDirectories: true)
        let output = paths.iconsDir.appending(path: "\(identity.slug).icns")
        if let logo = identity.logoPath {
            try IconGenerator.icns(fromImage: URL(fileURLWithPath: logo), output: output, shell: shell)
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
