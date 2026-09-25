import Foundation
import BrainmergeCore

/// What Settings > Command line says about the accounts' hooks: each account's, and whether the command line they all
/// call is there.
public struct HooksSummary: Equatable, Sendable {
    public let states: [HookInstaller.Health]
    public let commandLinePresent: Bool

    public init(states: [HookInstaller.Health], commandLinePresent: Bool) {
        self.states = states; self.commandLinePresent = commandLinePresent
    }

    public var allCurrent: Bool { !states.isEmpty && commandLinePresent && states.allSatisfy { $0 == .current } }

    /// Nil without an account: there is nothing to say.
    public var sentence: String? {
        if states.isEmpty { return nil }
        if !commandLinePresent, states.contains(where: { $0 != .missing }) { return "Some hooks point to a Brainmerge that is no longer there." }
        if allCurrent { return states.count == 1 ? "Hooks: 1 account, current." : "Hooks: \(states.count) accounts, all current." }
        return "Some hooks are missing or out of date."
    }

    /// Reads each account's settings file and looks for the command line the hooks call (following its link).
    static func read(_ manager: IdentityManager) -> HooksSummary {
        HooksSummary(states: ((try? manager.hooksHealth()) ?? []).map(\.1),
                     commandLinePresent: FileManager.default.isExecutableFile(atPath: manager.cliPath))
    }
}
