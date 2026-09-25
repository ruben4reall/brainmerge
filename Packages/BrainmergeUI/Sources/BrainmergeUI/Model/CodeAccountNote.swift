import BrainmergeCore

/// What the edit sheet says under Name about the account Claude Code last recorded, and the renames it offers from it.
/// Names stay the person's labels: nothing is renamed without a click, and the email itself never becomes a name
/// (a name signs memory commits and goes into Claude's instructions).
public struct CodeAccountNote: Equatable, Sendable {
    /// Another account, by slug and name.
    public struct Other: Equatable, Sendable {
        public let slug: String
        public let name: String
    }

    /// The email Claude Code uses; nil when it has not logged in with this account yet.
    public let email: String?
    /// Claude Code's display name, offered as the name when it differs from the name typed and no other account has it.
    public let suggestedName: String?
    /// The other account whose name is this email's local part, while this account's own name is not: the two names look
    /// swapped. Never when another account uses the same email: renaming does not fix one Claude account used twice.
    public let swapWith: Other?

    public static let privacy = "Brainmerge reads the email Claude Code shows for this account, never a password or a login token."

    /// Nil when Claude Code is off for this account: the sheet then says nothing about it.
    public static func make(for account: Account, typedName: String, among accounts: [Account]) -> CodeAccountNote? {
        guard account.identity.surfaces.cli else { return nil }
        guard let code = account.codeAccount else { return CodeAccountNote(email: nil, suggestedName: nil, swapWith: nil) }
        let others = accounts.filter { $0.id != account.id }
        var suggested: String?
        // An address is never offered: names end up in app names, Claude's instructions and memory commits.
        if let display = code.displayName.map(NameRules.clean), !display.isEmpty, !display.contains("@"),
           display.caseInsensitiveCompare(NameRules.clean(typedName)) != .orderedSame {
            var form = AddAccountForm(); form.name = display
            if form.validate(existing: others.map(\.identity)) == nil { suggested = display }
        }
        let local = normalized(String(code.email.split(separator: "@", maxSplits: 1).first ?? ""))
        let sharedEmail = others.contains { $0.codeAccount?.email.caseInsensitiveCompare(code.email) == .orderedSame }
        var swap: Other?
        if !sharedEmail, !local.isEmpty, normalized(account.identity.name) != local,
           let other = others.first(where: { normalized($0.identity.name) == local }) {
            swap = Other(slug: other.id, name: other.identity.name)
        }
        return CodeAccountNote(email: code.email, suggestedName: suggested, swapWith: swap)
    }

    /// Lowercased, letters and digits only: "Ag.En-Cy" and "Agency" compare equal.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    public var line: String {
        email.map { "Claude Code uses \($0)." } ?? "Claude Code is not logged in with this account."
    }
    public var useLabel: String? { suggestedName.map { "Use “\($0)”" } }
    public var swapLine: String? { swapWith.map { "This email looks like “\($0.name)”, the name of another account." } }
    public var swapLabel: String? { swapWith.map { "Swap names with \($0.name)" } }
    /// The swap is asked first: it renames both accounts at once, inside a sheet whose other changes wait for Save.
    public func swapQuestion(thisName: String) -> String { "Swap the names of \(thisName) and \(swapWith?.name ?? "")?" }
    public var swapExplanation: String { "Both accounts are renamed now, not when you save. Colors and photos stay with each account." }
}
