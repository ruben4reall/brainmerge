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
        // The quick opener's shortcut lives in the app's preferences on this Mac, not in its state: forgotten here too,
        // except for a demo or a test home (BRAINMERGE_HOME), which never touches the real app's preferences.
        if ProcessInfo.processInfo.environment["BRAINMERGE_HOME"]?.isEmpty ?? true {
            let domain = "ch.rubencatalao.brainmerge" as CFString
            for key in ["quickOpener.on", "quickOpener.keyCode", "quickOpener.modifiers", "quickOpener.key"] {
                CFPreferencesSetAppValue(key as CFString, nil, domain)
            }
            CFPreferencesAppSynchronize(domain)
        }
        print("Done: \(report.detachedAccounts) account(s) detached, \(report.copiedMemories) project memories copied next to their sessions, \(report.removedLaunchers) account app(s) removed. Quit Brainmerge if it is open (its shortcut stays until it quits), then move Brainmerge.app to the Trash.")
    }
}
