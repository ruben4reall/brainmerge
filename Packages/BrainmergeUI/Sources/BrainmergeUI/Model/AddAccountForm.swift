import Foundation
import BrainmergeCore

public struct AddAccountForm: Equatable, Sendable {
    /// Which memory the new account writes to: the shared one, another existing one, or one of its own.
    public enum MemoryChoice: Equatable, Sendable, Hashable { case shared, existing(String), own }

    public var name = ""
    public var memory: MemoryChoice = .shared
    public var tint: Tint = .blue
    public var logo: URL? = nil
    public var note = ""
    public var sharedHistory = false
    public var distinctIcon = false
    public var adoptCLI: URL? = nil
    public var adoptDesktop: URL? = nil
    public init() {}

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate(existing: [Identity]) -> String? {
        if trimmedName.isEmpty { return "Give this account a name." }
        let candidate = Identity(slug: "x", name: trimmedName).bundleDisplayName
        if existing.contains(where: { $0.bundleDisplayName.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return "There is already an account called \(trimmedName). Pick another name."
        }
        return nil
    }

    public var request: IdentityManager.AddRequest {
        var r = IdentityManager.AddRequest(name: trimmedName)
        r.tint = tint
        r.logo = logo
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        r.note = trimmedNote.isEmpty ? nil : trimmedNote
        r.sharedHistory = sharedHistory
        r.iconMode = distinctIcon ? .tintedClone : .launcher
        r.adoptCLIProfile = adoptCLI
        r.adoptDesktopData = adoptDesktop
        switch memory {
        case .shared: break
        case .existing(let id): r.brain = id
        case .own: r.ownBrain = true
        }
        return r
    }
}
