import Foundation
import ArgumentParser
import BrainmergeCore

struct BrainmergeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brainmerge",
        abstract: "Run every Claude account you own, side by side, with one shared brain.",
        version: BrainmergeInfo.version,
        subcommands: [BrainCommand.self, AdoptPrimary.self, IdentityCommand.self, Sync.self, WireCommand.self, TouchedCommand.self, UsageCommand.self, DoctorCommand.self, InstallCLI.self, UninstallCommand.self, CodeCommand.self, EnvCommand.self]
    )
}

extension Tint: ExpressibleByArgument {}

/// Called as `claude-<slug>` (the per-account links), it runs `code <slug>` with the rest of the arguments untouched.
@main
enum Entry {
    static func main() {
        BrainmergeCLI.main(ClaudeCodeTerminal.dispatch(CommandLine.arguments))
    }
}
