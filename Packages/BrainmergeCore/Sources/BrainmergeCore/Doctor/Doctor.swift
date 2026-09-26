import Foundation

/// Checks everything Brainmerge has set up, without fixing anything. Each finding says what to do: the command line
/// prints `detail` (with the command to run), the app shows `plain` (a sentence) and the button that `fix` names.
public struct Doctor: Sendable {
    public let paths: Paths
    public let store: StateStore
    public let claudeAppURL: URL
    public let cliPath: String
    /// Where apps the person made are looked for (see ExistingApps.folders).
    public let appFolders: [URL]
    public let git: GitAvailability

    public init(paths: Paths, store: StateStore, claudeAppURL: URL, cliPath: String, appFolders: [URL]? = nil, git: GitAvailability = .shared) {
        self.paths = paths; self.store = store; self.claudeAppURL = claudeAppURL; self.cliPath = cliPath; self.git = git
        self.appFolders = appFolders ?? ExistingApps.folders(for: paths)
    }

    /// What the app's button for a finding does. A finding only the person can settle (a login, a copy made by hand)
    /// has none.
    public enum Fix: Equatable, Hashable, Sendable, Codable {
        /// Every account attached to its memory again: managed block, hooks, memory links.
        case repairLinks(brainID: String)
        case rebuild(slug: String)
        case installCLI
        /// The folder where this memory lives now, or where to create it again.
        case chooseMemory(brainID: String)
        case repairHooks
        case installAppleTools
    }

    public struct Finding: Equatable, Sendable, Codable {
        public enum Level: String, Codable, Sendable { case ok, warning, error }
        public let level: Level
        public let title: String
        /// For the command line: what is wrong and, when it is, the command that mends it ("Run: …").
        public let detail: String
        /// For the app: one sentence, never a command.
        public let plain: String
        public let fix: Fix?
        public init(level: Level, title: String, detail: String, plain: String, fix: Fix? = nil) {
            self.level = level; self.title = title; self.detail = detail; self.plain = plain; self.fix = fix
        }
    }

    /// A path as the person reads it: the home folder as ~.
    func shown(_ path: String) -> String {
        let home = paths.home.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    public func run() -> [Finding] {
        var findings: [Finding] = []
        let fm = FileManager.default

        let claude: ClaudeApp?
        do {
            let detected = try ClaudeApp.detect(at: claudeAppURL)
            claude = detected
            findings.append(Finding(level: .ok, title: "Claude.app", detail: "Version \(detected.version) at \(claudeAppURL.path)",
                                    plain: "Claude \(detected.version) is installed."))
        } catch {
            claude = nil
            findings.append(Finding(level: .error, title: "Claude.app", detail: "\(error)",
                                    plain: "Brainmerge can't use the Claude app at \(shown(claudeAppURL.path)). Choose it under Where Claude is."))
        }

        findings.append(git.isAvailable
            ? Finding(level: .ok, title: "git", detail: "Apple's Command Line Tools are installed", plain: "Apple's Command Line Tools are installed.")
            : Finding(level: .error, title: "git", detail: "Apple's Command Line Tools are not installed. Run: xcode-select --install",
                      plain: "Apple's Command Line Tools are missing: the memory keeps its history with them.", fix: .installAppleTools))

        let state: AppState
        do { state = try store.load() } catch {
            findings.append(Finding(level: .error, title: "State", detail: "\(error)", plain: "Brainmerge can't read its list of accounts."))
            return findings
        }

        // Every memory the app knows, the default one first.
        var ready: [String: Brain] = [:]
        if state.brains.isEmpty {
            findings.append(Finding(level: .warning, title: "Memory", detail: "No memory configured. Run: brainmerge brain init",
                                    plain: "No memory is set up yet.", fix: .chooseMemory(brainID: AppState.defaultBrainID)))
        }
        for (index, folder) in state.brains.enumerated() {
            let candidate = Brain(root: folder.url)
            if candidate.isInitialized {
                ready[folder.id] = candidate
                let git = (try? BrainGit(brain: candidate, availability: self.git).log(limit: 1)) != nil
                findings.append(Finding(level: git ? .ok : .error, title: "Memory: \(folder.name)",
                                        detail: git ? "\(folder.path), git ready" : "\(folder.path): git repository unreadable",
                                        plain: git ? "The memory \(folder.name) is ready." : "The history of the memory \(folder.name) can't be read."))
            } else {
                // "brain init" only ever sets up the default memory: advised for it alone, with its own folder.
                let advice = index == 0 ? "Run: brainmerge brain init \(folder.path)"
                    : "Run: brainmerge brain forget \(folder.id), then brainmerge brain add --name \(folder.name) \(folder.path)"
                findings.append(Finding(level: .error, title: "Memory: \(folder.name)", detail: "Missing or not initialized at \(folder.path). \(advice)",
                                        plain: "The memory \(folder.name) is missing from \(shown(folder.path)).", fix: .chooseMemory(brainID: folder.id)))
            }
        }

        // Notes a save held back because they look like they hold a key: where, never the line.
        for folder in state.brains {
            for note in HeldStore(paths: paths, memoryID: folder.id).load().held {
                findings.append(Finding(level: .warning, title: "Memory: \(folder.name)",
                                        detail: "Not saved: \(note.sentence) Decide on the Memory screen.",
                                        plain: "Not saved in \(folder.name): \(note.sentence) Decide on the Memory screen."))
            }
        }

        let cliLink = paths.localBin.appending(path: "brainmerge")
        if let destination = try? fm.destinationOfSymbolicLink(atPath: cliLink.path), fm.fileExists(atPath: destination) {
            findings.append(Finding(level: .ok, title: "Command line", detail: "\(cliLink.path) -> \(destination)", plain: "The command line is installed."))
        } else {
            findings.append(Finding(level: .warning, title: "Command line", detail: "\(cliLink.path) missing. Run: brainmerge install-cli",
                                    plain: "The command line is not installed: every account's hooks call it.", fix: .installCLI))
        }

        // Apps the person made that open an account, read once for every account.
        let existingApps = claude == nil ? [] : ExistingApps(paths: paths, claudeAppURL: claudeAppURL, folders: appFolders).scan()
        for identity in state.identities {
            if let claude {
                for app in existingApps where app.opens(identity, in: paths) && app.runsOlderClaude(than: claude.version) {
                    findings.append(olderCopyFinding(identity, app: app, installed: claude.version))
                }
            }
            let memoryID = state.brain(for: identity)?.id ?? AppState.defaultBrainID
            let brain = state.brain(for: identity).flatMap { ready[$0.id] }
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists else {
                findings.append(missingProfileFinding(identity, profile: profile))
                continue
            }
            findings.append(hooksFinding(identity, profile: profile))
            let claudeMD = (try? String(contentsOf: profile.claudeMD, encoding: .utf8)) ?? ""
            let blockOK = ManagedBlock.contains(claudeMD) && (brain.map { claudeMD.contains($0.root.path) } ?? true)
            findings.append(blockOK
                ? Finding(level: .ok, title: "\(identity.name): CLAUDE.md", detail: "Managed block present",
                          plain: "The instructions of \(identity.name) point to its memory.")
                : Finding(level: .warning, title: "\(identity.name): CLAUDE.md", detail: "Managed block missing or stale. Run: brainmerge brain wire",
                          plain: "The instructions of \(identity.name) do not point to its memory.", fix: .repairLinks(brainID: memoryID)))
            if identity.surfaces.desktop, !identity.isPrimary {
                let app = identity.iconMode == .launcher
                    ? paths.launcherApp(name: identity.bundleDisplayName)
                    : paths.tintedClone(name: identity.bundleDisplayName)
                let rebuild = "Run: brainmerge identity rebuild \(identity.slug)"
                if fm.fileExists(atPath: app.path) {
                    if identity.iconMode == .tintedClone, let claude, identity.builtForClaudeVersion != claude.version {
                        let built = identity.builtForClaudeVersion ?? "?"
                        findings.append(Finding(level: .warning, title: "\(identity.name): launcher",
                                                detail: "Built for Claude \(built), installed \(claude.version). \(rebuild)",
                                                plain: "The app of \(identity.name) was built for Claude \(built), and Claude \(claude.version) is installed.",
                                                fix: .rebuild(slug: identity.slug)))
                    } else {
                        findings.append(Finding(level: .ok, title: "\(identity.name): launcher", detail: app.path, plain: "The app of \(identity.name) is in place."))
                    }
                } else {
                    findings.append(Finding(level: .error, title: "\(identity.name): launcher", detail: "Missing \(app.path). \(rebuild)",
                                            plain: "The app of \(identity.name) is missing.", fix: .rebuild(slug: identity.slug)))
                }
                let data = identity.desktopData(in: paths)
                findings.append(fm.fileExists(atPath: data.path)
                    ? Finding(level: .ok, title: "\(identity.name): data", detail: data.path, plain: "The Claude data folder of \(identity.name) is in place.")
                    : Finding(level: .warning, title: "\(identity.name): data", detail: data.path,
                              plain: "The Claude data folder of \(identity.name) is not there yet: Claude makes it when the account opens."))
            }
            if identity.isPrimary, let app = identity.appURL(in: paths) {
                findings.append(ownAppFinding(identity, app: app))
            }
            if identity.surfaces.desktop {
                let session = DesktopSession.hasSession(dataDir: identity.desktopData(in: paths))
                findings.append(session
                    ? Finding(level: .ok, title: "\(identity.name): login", detail: "Logged in", plain: "\(identity.name) is logged in.")
                    : Finding(level: .warning, title: "\(identity.name): login", detail: "Not logged in yet: open the account and log in its Claude window",
                              plain: "\(identity.name) is not logged in yet: open it and log in its Claude window."))
            }
            if let brain, let statuses = try? MemoryWiring(brain: brain, paths: paths, machineID: state.machineID).status(profile: profile) {
                for status in statuses {
                    findings.append(linkFinding(identity, project: status.name, state: status.state, brain: brain, memoryID: memoryID,
                                                known: state.brains.map(\.url)))
                }
            }
        }
        return findings
    }

    /// An account whose Claude Code folder is gone: nothing of it can be wired until the folder is back. Claude Code makes
    /// the first account's again when it starts; another account's is put back, or the account removed.
    func missingProfileFinding(_ identity: Identity, profile: CLIProfile) -> Finding {
        let path = profile.directory.path
        let missing = "The Claude Code folder of \(identity.name) is missing from \(shown(path))."
        if identity.isPrimary {
            return Finding(level: .error, title: "\(identity.name): profile",
                           detail: "Missing \(path). Start Claude Code once to make it again, then run: brainmerge brain wire",
                           plain: "\(missing) Start Claude Code once to make it again.")
        }
        return Finding(level: .error, title: "\(identity.name): profile",
                       detail: "Missing \(path). Put the folder back and run: brainmerge brain wire, or remove the account: brainmerge identity remove \(identity.slug)",
                       plain: "\(missing) Put it back, or remove the account.")
    }

    /// One project's memory link in an account's Claude Code folder. `known`: the memories in the state; a link into
    /// another folder Brainmerge made a memory of is said, since nothing saves the notes written there any more.
    func linkFinding(_ identity: Identity, project: String, state: ProjectLinkState, brain: Brain, memoryID: String,
                     known: [URL] = []) -> Finding {
        let title = "\(identity.name): memory \(project)"
        let wire = "Run: brainmerge brain wire"
        let repair = Fix.repairLinks(brainID: memoryID)
        if case .external(let target) = state, let root = Self.memoryRoot(containing: target),
           !known.contains(where: { $0.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path }) {
            return Finding(level: .warning, title: title,
                           detail: "points to \(target), in \(root.path): a memory Brainmerge no longer knows, so the notes written there are not saved. Run: brainmerge brain add --name NAME \(root.path), then brainmerge identity edit \(identity.slug) --brain ID",
                           plain: "The notes of \(project) for \(identity.name) go to \(shown(root.path)), a memory Brainmerge no longer knows: they are not saved.")
        }
        return switch state {
        case .linked: Finding(level: .ok, title: title, detail: "linked to \(brain.memoryDir(forProject: project).path)",
                              plain: "\(project) is linked to the memory for \(identity.name).")
        case .external(let target): Finding(level: .ok, title: title, detail: "kept as is, points to \(target)",
                                            plain: "\(project) keeps its own notes folder for \(identity.name).")
        case .missing: Finding(level: .warning, title: title, detail: "not linked yet. \(wire)",
                               plain: "\(project) is not linked to the memory yet for \(identity.name).", fix: repair)
        case .realDirectory: Finding(level: .warning, title: title, detail: "local folder, not in the brain. \(wire)",
                                     plain: "The notes of \(project) for \(identity.name) are in a local folder, outside the memory.", fix: repair)
        case .broken: Finding(level: .error, title: title, detail: "broken link. \(wire)",
                              plain: "The memory link of \(project) for \(identity.name) is broken.", fix: repair)
        }
    }

    /// The memory a folder is in, when Brainmerge made it one: a `memory` folder above it with BRAIN.md and `.brainmerge`
    /// beside it. Only looks for those names.
    static func memoryRoot(containing path: String) -> URL? {
        let fm = FileManager.default
        var folder = URL(fileURLWithPath: path).standardizedFileURL
        while folder.pathComponents.count > 1 {
            let parent = folder.deletingLastPathComponent()
            if folder.lastPathComponent == "memory" {
                let memory = Brain(root: parent)
                if fm.fileExists(atPath: memory.brainMD.path) && fm.fileExists(atPath: memory.metaDir.path) { return memory.root }
            }
            folder = parent
        }
        return nil
    }

    /// The account's hooks (memory saved when a turn ends, linked when a session starts): current, outdated, or missing.
    func hooksFinding(_ identity: Identity, profile: CLIProfile) -> Finding {
        let title = "\(identity.name): hooks"
        switch HookInstaller.health(settingsFile: profile.settingsFile, cliPath: cliPath, slug: identity.slug) {
        case .current: return Finding(level: .ok, title: title, detail: "current", plain: "The hooks of \(identity.name) are current.")
        case .outdated: return Finding(level: .warning, title: title, detail: "outdated. Run: brainmerge brain wire",
                                       plain: "The hooks of \(identity.name) are out of date.", fix: .repairHooks)
        case .missing: return Finding(level: .warning, title: title, detail: "missing in \(profile.settingsFile.path). Run: brainmerge brain wire",
                                      plain: "The hooks of \(identity.name) are missing: its memory is not saved when a turn ends.", fix: .repairHooks)
        }
    }

    /// A copy of Claude made by hand that opens this account with an older Claude: Brainmerge only says so, the person
    /// retires the copy. Its path only, never anything read from the account.
    func olderCopyFinding(_ identity: Identity, app: ExistingApp, installed: String) -> Finding {
        let advice = identity.isPrimary ? "Open \(identity.name) with Claude itself" : "Use Brainmerge's app for this account"
        return Finding(level: .warning, title: "\(identity.name): \(app.name)",
                       detail: "A copy of Claude \(app.claudeVersion ?? "?") made by hand, \(app.url.path), also opens this account, and Claude \(installed) is installed: an older Claude on the same data can damage it. \(advice), and move the copy to the Trash yourself once \(identity.name) is closed.",
                       plain: "\(app.name), a copy of Claude \(app.claudeVersion ?? "?") made by hand, also opens \(identity.name), and Claude \(installed) is installed: an older Claude on the same data can damage it. \(advice), and move the copy to the Trash yourself once \(identity.name) is closed.")
    }

    /// The primary's own app: there, and opening the Claude installed (it was built for another path if Claude moved).
    func ownAppFinding(_ identity: Identity, app: URL) -> Finding {
        let title = "\(identity.name): own app"
        let rebuild = "Run: brainmerge identity rebuild \(identity.slug)"
        guard FileManager.default.fileExists(atPath: app.path) else {
            return Finding(level: .error, title: title, detail: "Missing \(app.path). \(rebuild)",
                           plain: "The own app of \(identity.name) is missing.", fix: .rebuild(slug: identity.slug))
        }
        let config = (try? Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json")))
            .flatMap { try? JSONDecoder().decode(LauncherConfig.self, from: $0) }
        guard let opens = config?.openApp, opens == claudeAppURL.path else {
            return Finding(level: .warning, title: title, detail: "Opens \(config?.openApp ?? "nothing"), Claude is at \(claudeAppURL.path). \(rebuild)",
                           plain: "The own app of \(identity.name) opens another Claude than the one installed.", fix: .rebuild(slug: identity.slug))
        }
        return Finding(level: .ok, title: title, detail: app.path, plain: "The own app of \(identity.name) is in place.")
    }
}

public extension Array where Element == Doctor.Finding {
    var hasErrors: Bool { contains { $0.level == .error } }
}
