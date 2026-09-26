import ArgumentParser
import Darwin
import Foundation
import BrainmergeCore

/// Starts Claude Code on an account: the launcher's pattern, no shell, argv untouched, nothing credential-related read
/// or set. The only environment key this file reads is PATH; the shared Context reads BRAINMERGE_HOME, like every command.
struct CodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "code", abstract: "Start Claude Code on an account, with its memory.")

    @Argument(help: "The account's short name.") var slug: String
    @Argument(parsing: .captureForPassthrough, help: "Passed to Claude Code as they are.") var arguments: [String] = []

    func run() throws {
        let context = Context()
        guard let identity = try context.store.load().identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
        guard let claude = ClaudeCodeTerminal.resolve(path: getenv("PATH").map { String(cString: $0) }) else {
            FileHandle.standardError.write(Data((ClaudeCodeTerminal.notFound + "\n").utf8))
            throw ExitCode(127)
        }
        if identity.isPrimary { unsetenv("CLAUDE_CONFIG_DIR") } else { setenv("CLAUDE_CONFIG_DIR", identity.cliProfile(in: context.paths).path, 1) }
        if isatty(1) == 1 { FileHandle.standardOutput.write(Data(ClaudeCodeTerminal.title(name: identity.name).utf8)) }
        let argv = ["claude"] + arguments
        var cArguments = argv.map { strdup($0) } + [nil]
        execv(claude, &cArguments)
        FileHandle.standardError.write(Data("Could not start \(claude).\n".utf8))
        throw ExitCode(126)
    }
}
