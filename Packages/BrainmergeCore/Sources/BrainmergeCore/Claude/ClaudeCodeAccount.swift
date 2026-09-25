import Foundation

/// The account Claude Code last recorded in a profile, to tell accounts apart in the window: an email, a display name,
/// an organization name. Claude Code writes them for display in the `oauthAccount` entry of the profile's `.claude.json`
/// (see `CLIProfile.accountFile`). Only these three keys are decoded, by name: never the rest of the entry, its
/// identifiers, plan or limits, never anything else of the file. The login itself stays in the keychain, untouched.
///
/// The email is personal. It is shown in the window and never stored: not in the state, a memory, a commit,
/// Claude's instructions, a log, the command line's output or a message.
///
/// It is what Claude Code last recorded in that folder, not proof of a valid login. The format is Claude Code's own
/// and undocumented: anything unexpected gives nil, never an error.
public struct ClaudeCodeAccount: Equatable, Sendable {
    public let email: String
    public let displayName: String?
    /// nil for the personal default, "<email>'s Organization".
    public let organization: String?

    public init(email: String, displayName: String? = nil, organization: String? = nil) {
        self.email = email; self.displayName = displayName; self.organization = organization
    }

    /// The only keys of the entry ever decoded.
    enum Field: String, CodingKey, CaseIterable { case emailAddress, displayName, organizationName }
    public static let readFields: [String] = Field.allCases.map(\.stringValue)

    /// The account recorded in this profile; nil when the file is missing, nobody logged in (or logged out), or the file is not readable JSON.
    public static func read(profile: CLIProfile) -> ClaudeCodeAccount? {
        if case .found(let account) = reading(profile.accountFile) { return account }
        return nil
    }

    /// One read of the file: what it records (maybe nobody), or a file that cannot be read right now, such as one
    /// caught in the middle of a write.
    enum Reading: Equatable, Sendable { case found(ClaudeCodeAccount?), unreadable }

    static func reading(_ file: URL) -> Reading {
        guard let data = try? Data(contentsOf: file) else {
            return FileManager.default.fileExists(atPath: file.path) ? .unreadable : .found(nil)
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return .unreadable }
        return .found(root.account)
    }

    /// The file's top level: only the entry's key is looked up.
    private struct Root: Decodable {
        enum Key: String, CodingKey { case oauthAccount }
        let account: ClaudeCodeAccount?
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            account = (try? container.decodeIfPresent(Entry.self, forKey: .oauthAccount))?.account
        }
    }

    /// The entry: the three fields, each optional, so an entry with only an email still names the account.
    private struct Entry: Decodable {
        let account: ClaudeCodeAccount?
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Field.self)
            func text(_ key: Field) -> String? {
                let value = ((try? container.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : nil
            }
            guard let email = text(.emailAddress) else { account = nil; return }
            let organization = text(.organizationName)
            account = ClaudeCodeAccount(email: email, displayName: text(.displayName),
                                        organization: organization == email + "'s Organization" ? nil : organization)
        }
    }
}

/// Reads a profile's account again only when its file changed: Claude Code rewrites `.claude.json` often and the window
/// asks every minute. A file caught half written keeps the last account known, and is read again the next time.
public struct ClaudeCodeAccountCache: Sendable {
    private struct Entry: Sendable {
        let modified: Date
        let account: ClaudeCodeAccount?
    }
    private var entries: [String: Entry] = [:]

    public init() {}

    public mutating func account(profile: CLIProfile) -> ClaudeCodeAccount? {
        let file = profile.accountFile
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else {
            entries[file.path] = nil
            return nil
        }
        if let known = entries[file.path], known.modified == modified { return known.account }
        switch ClaudeCodeAccount.reading(file) {
        case .found(let account):
            entries[file.path] = Entry(modified: modified, account: account)
            return account
        case .unreadable:
            return entries[file.path]?.account
        }
    }
}
