import Foundation
import BrainmergeCore

extension AppModel {
    /// What the card's Copy Terminal Command copies: the account's own command when the links are on.
    public func terminalCommand(for slug: String) -> String {
        terminalCommands ? ClaudeCodeTerminal.linkPrefix + slug : "brainmerge code \(slug)"
    }

    /// Settings, Command line: makes each account's claude-<slug> link, or removes those that are Brainmerge's.
    @discardableResult
    public func setTerminalCommands(_ on: Bool) -> Task<Void, Never> {
        if terminalCommands != on { terminalCommands = on }
        let paths = self.paths, cli = commandLine()
        return save(.terminalCommands) { state in
            state.terminalCommands = on
            for identity in state.identities {
                if on, let cli { _ = try? CLIInstaller.linkAccount(paths: paths, slug: identity.slug, target: cli) }
                if !on { CLIInstaller.unlinkAccount(paths: paths, slug: identity.slug) }
            }
        }
    }
}
