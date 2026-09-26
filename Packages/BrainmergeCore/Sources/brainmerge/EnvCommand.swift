import ArgumentParser
import BrainmergeCore

/// `eval "$(brainmerge env work)"`: the variable that puts Claude Code on an account, for a whole shell.
struct EnvCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "env", abstract: "Print the line that points Claude Code at an account.")

    @Argument(help: "The account's short name.") var slug: String

    func run() throws {
        let context = Context()
        guard let identity = try context.store.load().identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        print(ClaudeCodeTerminal.envLine(configDir: identity.isPrimary ? nil : identity.cliProfile(in: context.paths).path))
    }
}
