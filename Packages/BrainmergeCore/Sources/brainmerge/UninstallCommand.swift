import ArgumentParser
import Foundation
import BrainmergeCore

/// Removes what Brainmerge set up and keeps every note and every login. Without --yes, only says what it would do.
struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Brainmerge's hooks, account apps, command line link and settings. Memories, Claude data and logins stay.")
    @Flag(help: "Do it. Without this flag the command only describes what would happen.") var yes = false

    func run() throws {
        let context = Context()
        let uninstaller = Uninstaller(paths: context.paths, store: context.store, manager: context.manager)
        let plan = try uninstaller.plan()
        print("Would remove:")
        for line in plan.removed { print("  - \(line)") }
        print("Would keep:")
        for line in plan.kept { print("  - \(line)") }
        guard yes else {
            print("Nothing done. Run again with --yes to proceed, then move Brainmerge.app to the Trash.")
            throw ExitCode(1)
        }
        let report = try uninstaller.run()
        print("Done: \(report.detachedAccounts) account(s) detached, \(report.copiedMemories) project memories copied next to their sessions, \(report.removedLaunchers) account app(s) removed. You can move Brainmerge.app to the Trash.")
    }
}
