import ArgumentParser
import Foundation
import BrainmergeCore

/// What every command shares: paths (BRAINMERGE_HOME), Claude.app (BRAINMERGE_CLAUDE_APP), state.
struct Context {
    let paths = Paths.current()
    let claudeAppURL = ClaudeApp.defaultURL()

    var store: StateStore { StateStore(paths: paths) }
    var cliLink: URL { paths.localBin.appending(path: "brainmerge") }

    var manager: IdentityManager {
        IdentityManager(paths: paths, store: store, launcherBinary: LauncherBuilder.siblingLauncher(),
                        cliPath: cliLink.path, claudeAppURL: claudeAppURL)
    }

    var doctor: Doctor { Doctor(paths: paths, store: store, claudeAppURL: claudeAppURL, cliPath: cliLink.path) }

    /// The default memory, or the one named by its id.
    func brain(id: String? = nil) throws -> Brain {
        let state = try store.load()
        if let id {
            guard let folder = state.brain(id: id) else { throw BrainmergeError.brainUnknown(id) }
            return Brain(root: folder.url)
        }
        guard let url = state.brainURL else { throw BrainmergeError.brainNotConfigured }
        return Brain(root: url)
    }

    /// The hooks call ~/.local/bin/brainmerge: this link must exist before installing them.
    func ensureCLILink(replaceValid: Bool = false) throws {
        let target = CLIInstaller.currentExecutable() ?? URL(fileURLWithPath: CommandLine.arguments[0])
        try CLIInstaller.ensureLink(paths: paths, target: target, replaceValid: replaceValid)
    }
}

struct InstallCLI: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install-cli", abstract: "Link brainmerge into ~/.local/bin.")
    func run() throws {
        let context = Context()
        try context.ensureCLILink(replaceValid: true)
        print("Linked \(context.cliLink.path). Make sure ~/.local/bin is in your PATH.")
    }
}
