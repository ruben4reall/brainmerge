import Foundation
import BrainmergeCore

/// Everything the edit sheet can change on an account, applied in one go.
public struct AccountEdit: Equatable, Sendable {
    public var name: String
    public var tint: Tint
    public var logo: URL?
    public var note: String
    /// A tinted local copy of Claude with its own icon and name in the Dock, instead of the launcher.
    public var distinctIcon: Bool
    /// The primary only: Brainmerge's app with this color or photo that opens Claude, to keep in the Dock.
    public var ownApp: Bool
    /// The memory the account writes to (a MemoryFolder id).
    public var memory: String
    /// The browser profile that goes with the account (Connections): saved with the rest, never before Save.
    public var browser: BrowserChoice?

    public init(account: Account, memory: String) {
        name = account.identity.name
        tint = account.identity.tint
        logo = account.identity.logoPath.map { URL(fileURLWithPath: $0) }
        note = account.identity.note ?? ""
        distinctIcon = account.identity.iconMode == .tintedClone
        ownApp = account.identity.ownApp == true
        self.memory = memory
        browser = account.identity.browser
    }

    var trimmedName: String { NameRules.clean(name) }
    var trimmedNote: String { NameRules.clean(note) }

    /// A name is required and must not clash with another account's.
    public func validate(existing: [Identity]) -> String? {
        var form = AddAccountForm(); form.name = name
        return form.validate(existing: existing)
    }
}
