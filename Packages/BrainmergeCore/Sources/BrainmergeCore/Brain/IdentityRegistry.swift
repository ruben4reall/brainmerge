import Foundation

/// `.brainmerge/identities.json`: name and tint of each slug, for attribution and display.
public struct IdentityRegistry: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var name: String
        public var tint: String
        public init(name: String, tint: String) { self.name = name; self.tint = tint }
    }

    public var identities: [String: Entry]
    public init(identities: [String: Entry] = [:]) { self.identities = identities }

    public static func load(_ file: URL) throws -> IdentityRegistry {
        guard let data = try ExistingFile.read(file), !data.isEmpty else { return IdentityRegistry() }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], raw["identities"] == nil {
            return IdentityRegistry()
        }
        return try JSONDecoder().decode(IdentityRegistry.self, from: data)
    }

    public func save(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: file, options: .atomic)
    }

    public mutating func record(_ identity: Identity) {
        identities[identity.slug] = Entry(name: identity.name, tint: identity.tint.rawValue)
    }
}
