import CryptoKit
import Foundation

/// The SHA-256 of a line, in hex: how a held line or a line you said is not a secret is recognized again, without the line.
public struct LineHash: Codable, Hashable, Sendable {
    public let hex: String
    public init(line: String) { hex = SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }.joined() }
    init(hex: String) { self.hex = hex }
    public init(from decoder: Decoder) throws { hex = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(hex) }
}

/// Reads the lines a save is about to add, never the rest of a note: `git diff --cached -U0` gives only the added lines,
/// with no context around them, so a line saved before is never read again. The value is never kept: a finding is a
/// path, a line number, a shape and a digest.
public enum SecretGuard {
    public struct Finding: Codable, Equatable, Sendable {
        public let path: String
        public let line: Int
        public let shape: SecretShape
        public let hash: LineHash
        public init(path: String, line: Int, shape: SecretShape, hash: LineHash) {
            self.path = path; self.line = line; self.shape = shape; self.hash = hash
        }
    }

    /// Every added line with a shape, unless `isAllowed(path, hash)`.
    public static func scan(diff: String, isAllowed: (String, LineHash) -> Bool) -> [Finding] {
        var findings: [Finding] = []
        var path: String?
        var next = 0
        var inHunk = false
        // By "\n" alone: a note's "\r" stays in its line, as git counts lines.
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") { path = nil; inHunk = false; continue }
            if !inHunk, line.hasPrefix("+++ ") { path = newPath(String(line.dropFirst(4))); continue }
            if line.hasPrefix("@@ ") { next = hunkStart(line); inHunk = true; continue }
            guard inHunk, let current = path else { continue }
            if line.hasPrefix("+") {
                let text = String(line.dropFirst())
                if let shape = SecretShapes.match(text) {
                    let hash = LineHash(line: text)
                    if !isAllowed(current, hash) { findings.append(Finding(path: current, line: next, shape: shape, hash: hash)) }
                }
                next += 1
            } else if line.hasPrefix(" ") {
                next += 1
            }
        }
        return findings
    }

    /// `b/<path>`, or git's quoted form for a name with quotes, control characters or bytes it escapes; nil for /dev/null.
    static func newPath(_ field: String) -> String? {
        let name = field.hasPrefix("\"") ? unquote(field) : field
        guard name.hasPrefix("b/") else { return nil }
        return String(name.dropFirst(2))
    }

    /// `@@ -a,b +c,d @@`: the new file's first line of the hunk.
    static func hunkStart(_ header: String) -> Int {
        guard let plus = header.firstIndex(of: "+") else { return 0 }
        return Int(header[header.index(after: plus)...].prefix { $0.isNumber }) ?? 0
    }

    /// Git's C-style quoting: backslash escapes and octal bytes, read back as UTF-8.
    static func unquote(_ quoted: String) -> String {
        var bytes: [UInt8] = []
        var chars = Array(quoted.utf8.dropFirst())
        if chars.last == UInt8(ascii: "\"") { chars.removeLast() }
        var index = 0
        while index < chars.count {
            let c = chars[index]
            guard c == UInt8(ascii: "\\"), index + 1 < chars.count else { bytes.append(c); index += 1; continue }
            let e = chars[index + 1]
            let simple: [UInt8: UInt8] = [UInt8(ascii: "n"): 10, UInt8(ascii: "t"): 9, UInt8(ascii: "r"): 13, UInt8(ascii: "a"): 7,
                                          UInt8(ascii: "b"): 8, UInt8(ascii: "f"): 12, UInt8(ascii: "v"): 11]
            if let byte = simple[e] { bytes.append(byte); index += 2; continue }
            let octal = UInt8(ascii: "0")...UInt8(ascii: "7")
            if index + 3 < chars.count, chars[(index + 1)...(index + 3)].allSatisfy(octal.contains),
               let value = UInt8(String(decoding: chars[(index + 1)...(index + 3)], as: UTF8.self), radix: 8) {
                bytes.append(value); index += 4; continue
            }
            bytes.append(e); index += 2
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A note a save held back: which account wrote it (nil for your own edits), where, what it looks like, and the digest of
/// the line. Never the line.
public struct HeldNote: Codable, Equatable, Identifiable, Sendable {
    public let account: String?
    public let path: String
    public let line: Int
    public let shape: SecretShape
    public let hash: LineHash
    public init(account: String?, path: String, line: Int, shape: SecretShape, hash: LineHash) {
        self.account = account; self.path = path; self.line = line; self.shape = shape; self.hash = hash
    }
    public var id: String { "\(account ?? "")|\(path)|\(line)|\(hash.hex)" }
    /// "acme-api/deploy.md, line 12, looks like a GitHub token."
    public var sentence: String {
        let shown = path.hasPrefix("memory/") ? String(path.dropFirst("memory/".count)) : path
        return "\(shown), line \(line), looks like \(shape.label)."
    }
}

/// What a memory's saves held back, and the one-time "Save anyway" allowances, kept in Application Support
/// (`held/<memory>.json`), outside the memory: they are this Mac's, never committed.
public struct HeldNotes: Codable, Equatable, Sendable {
    public struct Allowance: Codable, Equatable, Sendable {
        public let account: String?
        public let path: String
        public let hash: LineHash
    }
    public var held: [HeldNote] = []
    public var allowed: [Allowance] = []
    public init() {}

    func allows(account: String?, path: String, hash: LineHash) -> Bool {
        allowed.contains { $0.account == account && $0.path == path && $0.hash == hash }
    }

    /// After a save by `account` of `requested` paths: its entries for them are replaced by what this save `found`, and
    /// its allowances for the paths it staged are used up.
    mutating func record(account: String?, requested: Set<String>, staged: Set<String>, found: [HeldNote]) {
        held.removeAll { $0.account == account && requested.contains($0.path) }
        held += found
        allowed.removeAll { $0.account == account && staged.contains($0.path) }
    }
}

public struct HeldStore: Sendable {
    public let file: URL
    public init(paths: Paths, memoryID: String) {
        file = paths.appSupport.appending(path: "held", directoryHint: .isDirectory).appending(path: "\(memoryID).json")
    }

    /// An unreadable or missing file holds nothing.
    public func load() -> HeldNotes {
        guard let data = try? Data(contentsOf: file) else { return HeldNotes() }
        return (try? JSONDecoder().decode(HeldNotes.self, from: data)) ?? HeldNotes()
    }

    /// Nothing held and nothing allowed: the file goes.
    public func save(_ notes: HeldNotes) throws {
        if notes.held.isEmpty && notes.allowed.isEmpty { try? FileManager.default.removeItem(at: file); return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(notes).write(to: file, options: .atomic)
    }
}

/// The lines you said are not secrets, by digest only, in the memory (`.brainmerge/not-secrets.json`, saved with your own
/// edits): every account attached to the memory then saves them.
public enum NotSecrets {
    struct File: Codable { var hashes: [String] }

    public static func hashes(in brain: Brain) -> Set<String> {
        guard let data = try? Data(contentsOf: brain.notSecretsFile), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(file.hashes)
    }

    public static func add(_ hash: LineHash, in brain: Brain) throws {
        let all = hashes(in: brain).union([hash.hex]).sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
        try encoder.encode(File(hashes: all)).write(to: brain.notSecretsFile, options: .atomic)
    }
}

/// The two answers to a held note, run under the memory's lock.
public enum HeldDecision {
    /// "It's not a secret": the line's digest joins the memory's list; every note held for that line is saved by its
    /// writer's next save.
    public static func notASecret(_ note: HeldNote, brain: Brain, store: HeldStore) throws {
        try NotSecrets.add(note.hash, in: brain)
        var notes = store.load()
        notes.held.removeAll { $0.hash == note.hash }
        try store.save(notes)
    }

    /// "Save anyway": this note, this line, once, at the next save of the account that wrote it.
    public static func saveAnyway(_ note: HeldNote, store: HeldStore) throws {
        var notes = store.load()
        notes.held.removeAll { $0 == note }
        notes.allowed.append(HeldNotes.Allowance(account: note.account, path: note.path, hash: note.hash))
        try store.save(notes)
    }
}
