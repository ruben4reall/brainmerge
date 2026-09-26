import Foundation

/// Checks everything Brainmerge has set up, without fixing anything. Each finding says what to do.
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

    public struct Finding: Equatable, Sendable, Codable {
        public enum Level: String, Codable, Sendable { case ok, warning, error }
        public let level: Level
        public let title: String
        public let detail: String
        public init(level: Level, title: String, detail: String) { self.level = level; self.title = title; self.detail = detail }
    }

    public func run() -> [Finding] {
        var findings: [Finding] = []
        let fm = FileManager.default

        let claude: ClaudeApp?
        do {
            let detected = try ClaudeApp.detect(at: claudeAppURL)
            claude = detected
            findings.append(Finding(level: .ok, title: "Claude.app", detail: "Version \(detected.version) at \(claudeAppURL.path)"))
        } catch {
            claude = nil
            findings.append(Finding(level: .error, title: "Claude.app", detail: "\(error)"))
        }

        findings.append(git.isAvailable
            ? Finding(level: .ok, title: "git", detail: "Apple's Command Line Tools are installed")
            : Finding(level: .error, title: "git", detail: "Apple's Command Line Tools are not installed. Run: xcode-select --install"))

        let state: AppState
        do { state = try store.load() } catch {
            findings.append(Finding(level: .error, title: "State", detail: "\(error)"))
            return findings
        }

        // Every memory the app knows, the default one first.
        var ready: [String: Brain] = [:]
        if state.brains.isEmpty {
            findings.append(Finding(level: .warning, title: "Memory", detail: "No memory configured. Run: brainmerge brain init"))
        }
        for (index, folder) in state.brains.enumerated() {
            let candidate = Brain(root: folder.url)
            if candidate.isInitialized {
                ready[folder.id] = candidate
                let git = (try? BrainGit(brain: candidate, availability: self.git).log(limit: 1)) != nil
                findings.append(Finding(level: git ? .ok : .error, title: "Memory: \(folder.name)",
                                        detail: git ? "\(folder.path), git ready" : "\(folder.path): git repository unreadable"))
            } else {
                // "brain init" moves the default memory: only ever advised for it.
                let advice = index == 0 ? "Run: brainmerge brain init \(folder.path)"
                    : "Run: brainmerge brain forget \(folder.id), then brainmerge brain add --name \(folder.name) \(folder.path)"
                findings.append(Finding(level: .error, title: "Memory: \(folder.name)", detail: "Missing or not initialized at \(folder.path). \(advice)"))
            }
        }

        // Notes a save held back because they look like they hold a key: where, never the line.
        for folder in state.brains {
            for note in HeldStore(paths: paths, memoryID: folder.id).load().held {
                findings.append(Finding(level: .warning, title: "Memory: \(folder.name)",
                                        detail: "Not saved: \(note.sentence) Decide on the Memory screen."))
            }
        }

        let cliLink = paths.localBin.appending(path: "brainmerge")
        if let destination = try? fm.destinationOfSymbolicLink(atPath: cliLink.path), fm.fileExists(atPath: destination) {
            findings.append(Finding(level: .ok, title: "Command line", detail: "\(cliLink.path) -> \(destination)"))
        } else {
            findings.append(Finding(level: .warning, title: "Command line", detail: "\(cliLink.path) missing. Run: brainmerge install-cli"))
        }

        // Apps the person made that open an account, read once for every account.
        let existingApps = claude == nil ? [] : ExistingApps(paths: paths, claudeAppURL: claudeAppURL, folders: appFolders).scan()
        for identity in state.identities {
            if let claude {
                for app in existingApps where app.opens(identity, in: paths) && app.runsOlderClaude(than: claude.version) {
                    findings.append(olderCopyFinding(identity, app: app, installed: claude.version))
                }
            }
            let brain = state.brain(for: identity).flatMap { ready[$0.id] }
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists else {
                findings.append(Finding(level: .error, title: "\(identity.name): profile", detail: "Missing \(profile.directory.path)"))
                continue
            }
            findings.append(hooksFinding(identity, profile: profile))
            let claudeMD = (try? String(contentsOf: profile.claudeMD, encoding: .utf8)) ?? ""
            let blockOK = ManagedBlock.contains(claudeMD) && (brain.map { claudeMD.contains($0.root.path) } ?? true)
            findings.append(Finding(level: blockOK ? .ok : .warning, title: "\(identity.name): CLAUDE.md",
                                    detail: blockOK ? "Managed block present" : "Managed block missing or stale. Run: brainmerge brain wire"))
            if identity.surfaces.desktop, !identity.isPrimary {
                let app = identity.iconMode == .launcher
                    ? paths.launcherApp(name: identity.bundleDisplayName)
                    : paths.tintedClone(name: identity.bundleDisplayName)
                if fm.fileExists(atPath: app.path) {
                    let stale = identity.iconMode == .tintedClone && claude != nil && identity.builtForClaudeVersion != claude!.version
                    findings.append(Finding(level: stale ? .warning : .ok, title: "\(identity.name): launcher",
                                            detail: stale ? "Built for Claude \(identity.builtForClaudeVersion ?? "?"), installed \(claude!.version). Run: brainmerge identity rebuild \(identity.slug)" : app.path))
                } else {
                    findings.append(Finding(level: .error, title: "\(identity.name): launcher",
                                            detail: "Missing \(app.path). Run: brainmerge identity rebuild \(identity.slug)"))
                }
                let data = identity.desktopData(in: paths)
                findings.append(Finding(level: fm.fileExists(atPath: data.path) ? .ok : .warning, title: "\(identity.name): data",
                                        detail: data.path))
            }
            if identity.isPrimary, let app = identity.appURL(in: paths) {
                findings.append(ownAppFinding(identity, app: app))
            }
            if identity.surfaces.desktop {
                let session = DesktopSession.hasSession(dataDir: identity.desktopData(in: paths))
                findings.append(Finding(level: session ? .ok : .warning, title: "\(identity.name): login",
                                        detail: session ? "Logged in" : "Not logged in yet: open the account and log in its Claude window"))
            }
            if let brain, let statuses = try? MemoryWiring(brain: brain, paths: paths, machineID: state.machineID).status(profile: profile) {
                for status in statuses {
                    let (level, detail): (Finding.Level, String) = switch status.state {
                    case .linked: (.ok, "linked to \(brain.memoryDir(forProject: status.name).path)")
                    case .external(let target): (.ok, "kept as is, points to \(target)")
                    case .missing: (.warning, "not linked yet. Run: brainmerge brain wire")
                    case .realDirectory: (.warning, "local folder, not in the brain. Run: brainmerge brain wire")
                    case .broken: (.error, "broken link. Run: brainmerge brain wire")
                    }
                    findings.append(Finding(level: level, title: "\(identity.name): memory \(status.name)", detail: detail))
                }
            }
        }
        return findings
    }

    /// The account's hooks (memory saved when a turn ends, linked when a session starts): current, outdated, or missing.
    func hooksFinding(_ identity: Identity, profile: CLIProfile) -> Finding {
        let title = "\(identity.name): hooks"
        switch HookInstaller.health(settingsFile: profile.settingsFile, cliPath: cliPath, slug: identity.slug) {
        case .current: return Finding(level: .ok, title: title, detail: "current")
        case .outdated: return Finding(level: .warning, title: title, detail: "outdated. Run: brainmerge brain wire")
        case .missing: return Finding(level: .warning, title: title, detail: "missing in \(profile.settingsFile.path). Run: brainmerge brain wire")
        }
    }

    /// A copy of Claude made by hand that opens this account with an older Claude: Brainmerge only says so, the person
    /// retires the copy. Its path only, never anything read from the account.
    func olderCopyFinding(_ identity: Identity, app: ExistingApp, installed: String) -> Finding {
        let advice = identity.isPrimary ? "Open \(identity.name) with Claude itself" : "Use Brainmerge's app for this account"
        return Finding(level: .warning, title: "\(identity.name): \(app.name)",
                       detail: "A copy of Claude \(app.claudeVersion ?? "?") made by hand, \(app.url.path), also opens this account, and Claude \(installed) is installed: an older Claude on the same data can damage it. \(advice), and move the copy to the Trash yourself once \(identity.name) is closed.")
    }

    /// The primary's own app: there, and opening the Claude installed (it was built for another path if Claude moved).
    func ownAppFinding(_ identity: Identity, app: URL) -> Finding {
        let title = "\(identity.name): own app"
        let rebuild = "Run: brainmerge identity rebuild \(identity.slug)"
        guard FileManager.default.fileExists(atPath: app.path) else {
            return Finding(level: .error, title: title, detail: "Missing \(app.path). \(rebuild)")
        }
        let config = (try? Data(contentsOf: app.appending(path: "Contents/Resources/brainmerge.json")))
            .flatMap { try? JSONDecoder().decode(LauncherConfig.self, from: $0) }
        guard let opens = config?.openApp, opens == claudeAppURL.path else {
            return Finding(level: .warning, title: title, detail: "Opens \(config?.openApp ?? "nothing"), Claude is at \(claudeAppURL.path). \(rebuild)")
        }
        return Finding(level: .ok, title: title, detail: app.path)
    }
}

public extension Array where Element == Doctor.Finding {
    var hasErrors: Bool { contains { $0.level == .error } }
}
