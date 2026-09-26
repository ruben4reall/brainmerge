import Foundation

/// Undoes everything Brainmerge set up, and deletes nothing that is the person's: memories, Claude data folders
/// and logins stay. Each project's memory link becomes a real folder (a copy of its notes), so Claude Code keeps
/// working exactly as before Brainmerge.
public struct Uninstaller: Sendable {
    public let paths: Paths
    public let store: StateStore
    public let manager: IdentityManager

    public init(paths: Paths, store: StateStore, manager: IdentityManager) {
        self.paths = paths; self.store = store; self.manager = manager
    }

    /// What goes and what stays, in sentences, for a confirmation.
    public struct Plan: Equatable, Sendable {
        public var removed: [String]
        public var kept: [String]
    }

    public struct Report: Equatable, Sendable {
        public var detachedAccounts = 0
        public var copiedMemories = 0
        public var removedLaunchers = 0
        public init() {}
    }

    public func plan() throws -> Plan {
        let state = try store.load()
        var removed: [String] = []
        let profiles = state.identities.filter { CLIProfile(directory: $0.cliProfile(in: paths)).exists }.count
        if profiles > 0 { removed.append("The memory hooks and the Brainmerge block in \(profiles) Claude Code profile\(profiles > 1 ? "s" : "")") }
        let launchers = state.identities.filter { $0.appURL(in: paths) != nil }.count
        if launchers > 0 { removed.append("\(launchers) account app\(launchers > 1 ? "s" : "") in \(paths.launchersDir.path)") }
        if Self.isOurCommandLineLink(paths.localBin.appending(path: "brainmerge")) {
            removed.append("The command line link \(paths.localBin.appending(path: "brainmerge").path)")
        }
        let commands = state.identities.map(\.slug).filter { CLIInstaller.hasAccountLink(paths: paths, slug: $0) }
        if !commands.isEmpty {
            let names = commands.map { ClaudeCodeTerminal.linkPrefix + $0 }.joined(separator: ", ")
            removed.append("The terminal command\(commands.count > 1 ? "s" : "") \(names) in \(paths.localBin.path)")
        }
        removed.append("Brainmerge's settings, icons and usage cache in \(paths.appSupport.path)")
        var kept: [String] = []
        for folder in state.brains { kept.append("The memory \(folder.name) at \(folder.path)") }
        kept.append("Each project keeps a copy of its notes next to its sessions, so Claude Code goes on remembering")
        for identity in state.identities where !identity.isPrimary {
            kept.append("\(identity.name)'s Claude data and login (\(identity.desktopData(in: paths).path)) and its Claude Code folder (\(identity.cliProfile(in: paths).path))")
        }
        kept.append("Your Claude app, and the data and login of your first account")
        kept.append("Any memory link you made yourself (to a folder Brainmerge does not manage)")
        return Plan(removed: removed, kept: kept)
    }

    /// Refuses while a secondary account is open (its files are in use). Then detaches, copies, removes. The primary's own
    /// app goes even while Claude runs: it only opens Claude, which stays as it is.
    @discardableResult
    public func run() throws -> Report {
        let state = try store.load()
        let fm = FileManager.default
        for identity in state.identities where !identity.isPrimary {
            if (try? manager.isRunning(identity)) == true { throw BrainmergeError.identityRunning(identity.slug) }
        }
        var report = Report()
        let knownRoots = state.brains.map(\.url)
        for identity in state.identities {
            let profile = CLIProfile(directory: identity.cliProfile(in: paths))
            if profile.exists {
                try manager.detachBrain(from: identity)
                report.copiedMemories += try Self.materializeLinks(in: profile, knownRoots: knownRoots)
                report.detachedAccounts += 1
            }
            for app in manager.apps(of: identity) where fm.fileExists(atPath: app.path) {
                if manager.registerLaunchers { _ = try? manager.shell.run(LauncherBuilder.lsregister, ["-u", app.path]) }
                try fm.removeItem(at: app)
                report.removedLaunchers += 1
            }
        }
        let link = paths.localBin.appending(path: "brainmerge")
        if Self.isOurCommandLineLink(link) { try fm.removeItem(at: link) }
        for identity in state.identities { CLIInstaller.unlinkAccount(paths: paths, slug: identity.slug) }
        for dir in [paths.appSupport, paths.logsDir] where fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        if let entries = try? fm.contentsOfDirectory(atPath: paths.launchersDir.path), entries.allSatisfy({ $0.hasPrefix(".") }) {
            try? fm.removeItem(at: paths.launchersDir)
        }
        return report
    }

    /// The link in ~/.local/bin is ours when it points at the command line inside a Brainmerge app bundle.
    static func isOurCommandLineLink(_ link: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return CLIInstaller.madeByBrainmerge(destination: destination)
    }

    /// Every `projects/<slug>/memory` link that points into one of Brainmerge's memories becomes a real folder holding
    /// a copy of it (copied beside it first, then put in place, so a failed copy leaves the link as it was). A broken
    /// link into a memory is removed. A link the person made to a folder of their own is left alone.
    /// Returns the number of copies made.
    static func materializeLinks(in profile: CLIProfile, knownRoots: [URL]) throws -> Int {
        let fm = FileManager.default
        let memories = knownRoots.map { Brain(root: $0).memoryDir.standardizedFileURL.path + "/" }
        var copies = 0
        guard let entries = try? fm.contentsOfDirectory(atPath: profile.projectsDir.path) else { return 0 }
        for entry in entries where !entry.hasPrefix(".") {
            let link = profile.projectsDir.appending(path: entry, directoryHint: .isDirectory).appending(path: "memory")
            guard let attributes = try? fm.attributesOfItem(atPath: link.path),
                  (attributes[.type] as? FileAttributeType) == .typeSymbolicLink,
                  let destination = try? fm.destinationOfSymbolicLink(atPath: link.path) else { continue }
            let target = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
            guard memories.contains(where: { target.path.hasPrefix($0) }) else { continue }
            if fm.fileExists(atPath: target.path) {
                let staging = link.deletingLastPathComponent().appending(path: ".memory-copy")
                if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
                try fm.copyItem(at: target, to: staging)
                try fm.removeItem(at: link)
                try fm.moveItem(at: staging, to: link)
                copies += 1
            } else {
                try fm.removeItem(at: link)
            }
        }
        return copies
    }
}
