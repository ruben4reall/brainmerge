import ArgumentParser
import BrainmergeCore

@main
struct BrainmergeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brainmerge",
        abstract: "Run every Claude account you own, side by side, with one shared brain.",
        version: BrainmergeInfo.version,
        subcommands: [BrainCommand.self, AdoptPrimary.self, IdentityCommand.self, Sync.self, WireCommand.self, TouchedCommand.self, UsageCommand.self, DoctorCommand.self, InstallCLI.self, UninstallCommand.self]
    )
}

extension Tint: ExpressibleByArgument {}
