import Foundation

/// Checks everything Brainmerge has set up, without fixing anything. Each finding says what to do.
public struct Doctor: Sendable {
    public let paths: Paths
    public let store: StateStore
    public let claudeAppURL: URL
    public let cliPath: String

    public init(paths: Paths, store: StateStore, claudeAppURL: URL, cliPath: String) {
        self.paths = paths; self.store = store; self.claudeAppURL = claudeAppURL; self.cliPath = cliPath
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
                let git = (try? BrainGit(brain: candidate).log(limit: 1)) != nil
                findings.append(Finding(level: git ? .ok : .error, title: "Memory: \(folder.name)",
                                        detail: git ? "\(folder.path), git ready" : "\(folder.path): git repository unreadable"))
            } else {
                // "brain init" moves the default memory: only ever advised for it.
                let advice = index == 0 ? "Run: brainmerge brain init \(folder.path)"
                    : "Run: brainmerge brain forget \(folder.id), then brainmerge brain add --name \(folder.name) \(folder.path)"
                findings.append(Finding(level: .error, title: "Memory: \(folder.name)", detail: "Missing or not initialized at \(folder.path). \(advice)"))
            }
        }

        let cliLink = paths.localBin.appending(path: "brainmerge")
        if let destination = try? fm.destinationOfSymbolicLink(atPath: cliLink.path), fm.fileExists(atPath: destination) {
            findings.append(Finding(level: .ok, title: "Command line", detail: "\(cliLink.path) -> \(destination)"))
        } else {
            findings.append(Finding(level: .warning, title: "Command line", detail: "\(cliLink.path) missing. Run: brainmerge install-cli"))
        }

        for identity in state.identities {
            let brain = state.brain(for: identity).flatMap { ready[$0.id] }
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            guard profile.exists else {
                findings.append(Finding(level: .error, title: "\(identity.name): profile", detail: "Missing \(profile.directory.path)"))
                continue
            }
            let hook = (try? HookInstaller.isInstalled(settingsFile: profile.settingsFile)) ?? false
            findings.append(Finding(level: hook ? .ok : .warning, title: "\(identity.name): hook",
                                    detail: hook ? "Stop hook installed" : "Stop hook missing in \(profile.settingsFile.path). Run: brainmerge brain wire"))
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
}

public extension Array where Element == Doctor.Finding {
    var hasErrors: Bool { contains { $0.level == .error } }
}
