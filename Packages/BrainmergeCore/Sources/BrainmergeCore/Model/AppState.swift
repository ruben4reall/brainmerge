import Foundation

public enum BrainLanguage: String, Codable, Sendable { case en, fr }

/// A memory the app knows by name: a Brain folder. The first one in the list is the default, shared one.
public struct MemoryFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public init(id: String, name: String, path: String) { self.id = id; self.name = name; self.path = path }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

public struct AppState: Codable, Equatable, Sendable {
    public static let currentSchema = 2
    public static let defaultBrainID = "shared"
    public static let defaultBrainName = "Shared"

    public var schemaVersion: Int
    public var machineID: String
    /// Every memory folder; the first one is the default, the one accounts use unless they name another.
    public var brains: [MemoryFolder]
    public var identities: [Identity]
    public var autoRebuild: Bool
    public var brainLanguage: BrainLanguage
    /// The app that opens the memory folder: a bundle identifier, "path:<app>" for any other app, nil for the folder itself.
    public var notesApp: String?
    /// Brainmerge's icon in the menu bar. On unless the person turned it off.
    public var menuBarIcon: Bool
    /// `claude-<slug>` next to `brainmerge` in ~/.local/bin, one per account. Off unless the person turns it on.
    public var terminalCommands = false
    /// The Obsidian vault the Memory screen's graph shows, by its folder; nil shows the Brainmerge memory.
    public var graphVault: String?
    /// The Brainmerge memory the Memory screen shows, by its id; nil, or one forgotten since, shows the default one.
    public var graphMemory: String?
    /// The Claude app the person chose in Settings, by its path; nil finds it (see ClaudeLocator).
    public var claudeAppPath: String?
    /// The person's own edits to the notes, outside Claude, are saved in the memory's history as You (see OwnEdits).
    public var saveOwnEdits: Bool = true
    /// The macOS and Claude versions the app last checked its setup after (see Doctor): a new one runs the check once.
    public var lastCheckedMacOS: String?
    public var lastCheckedClaude: String?

    public init(schemaVersion: Int = AppState.currentSchema, machineID: String = UUID().uuidString,
                brainPath: String? = nil, identities: [Identity] = [], autoRebuild: Bool = true,
                brainLanguage: BrainLanguage = .en, notesApp: String? = nil, brains: [MemoryFolder] = [], menuBarIcon: Bool = true, graphVault: String? = nil) {
        self.schemaVersion = schemaVersion; self.machineID = machineID; self.menuBarIcon = menuBarIcon; self.graphVault = graphVault
        self.identities = identities; self.autoRebuild = autoRebuild; self.brainLanguage = brainLanguage; self.notesApp = notesApp
        self.brains = brains
        if brains.isEmpty, let brainPath { self.brains = [MemoryFolder(id: Self.defaultBrainID, name: Self.defaultBrainName, path: brainPath)] }
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, machineID, brainPath, brains, identities, autoRebuild, brainLanguage, notesApp, menuBarIcon, graphVault, graphMemory, claudeAppPath, saveOwnEdits, terminalCommands, lastCheckedMacOS, lastCheckedClaude }

    /// Schema 1 (a single `brainPath`) becomes a list with one memory called Shared.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        machineID = try c.decode(String.self, forKey: .machineID)
        identities = try c.decode([Identity].self, forKey: .identities)
        autoRebuild = try c.decode(Bool.self, forKey: .autoRebuild)
        brainLanguage = try c.decode(BrainLanguage.self, forKey: .brainLanguage)
        notesApp = try c.decodeIfPresent(String.self, forKey: .notesApp)
        // Added without a schema bump: a file written before it keeps the icon on.
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? true
        graphVault = try c.decodeIfPresent(String.self, forKey: .graphVault)
        graphMemory = try c.decodeIfPresent(String.self, forKey: .graphMemory)
        claudeAppPath = try c.decodeIfPresent(String.self, forKey: .claudeAppPath)
        // Added without a schema bump, like the menu bar icon: a file written before it saves the person's edits.
        saveOwnEdits = try c.decodeIfPresent(Bool.self, forKey: .saveOwnEdits) ?? true
        terminalCommands = try c.decodeIfPresent(Bool.self, forKey: .terminalCommands) ?? false
        // Added without a schema bump too: a file written before has checked after no version yet.
        lastCheckedMacOS = try c.decodeIfPresent(String.self, forKey: .lastCheckedMacOS)
        lastCheckedClaude = try c.decodeIfPresent(String.self, forKey: .lastCheckedClaude)
        let list = try c.decodeIfPresent([MemoryFolder].self, forKey: .brains) ?? []
        if list.isEmpty, let path = try c.decodeIfPresent(String.self, forKey: .brainPath) {
            brains = [MemoryFolder(id: Self.defaultBrainID, name: Self.defaultBrainName, path: path)]
        } else {
            brains = list
        }
    }

    /// `brainPath` is written too (the default memory's folder), for anything that reads the file by hand.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(machineID, forKey: .machineID)
        try c.encodeIfPresent(brainPath, forKey: .brainPath)
        try c.encode(brains, forKey: .brains)
        try c.encode(identities, forKey: .identities)
        try c.encode(autoRebuild, forKey: .autoRebuild)
        try c.encode(brainLanguage, forKey: .brainLanguage)
        try c.encodeIfPresent(notesApp, forKey: .notesApp)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encodeIfPresent(graphVault, forKey: .graphVault)
        try c.encodeIfPresent(graphMemory, forKey: .graphMemory)
        try c.encodeIfPresent(claudeAppPath, forKey: .claudeAppPath)
        try c.encode(saveOwnEdits, forKey: .saveOwnEdits)
        try c.encode(terminalCommands, forKey: .terminalCommands)
        try c.encodeIfPresent(lastCheckedMacOS, forKey: .lastCheckedMacOS)
        try c.encodeIfPresent(lastCheckedClaude, forKey: .lastCheckedClaude)
    }

    /// The default memory's folder. Setting it moves the default memory to that folder, or creates it.
    public var brainPath: String? {
        get { brains.first?.path }
        set {
            if let newValue {
                if brains.isEmpty { brains = [MemoryFolder(id: Self.defaultBrainID, name: Self.defaultBrainName, path: newValue)] }
                else { brains[0].path = newValue }
            } else if !brains.isEmpty {
                brains.removeFirst()
            }
        }
    }
    public var brainURL: URL? { defaultBrain?.url }
    public var defaultBrain: MemoryFolder? { brains.first }
    public func brain(id: String) -> MemoryFolder? { brains.first { $0.id == id } }
    /// The identity's memory: the one it names while it exists, otherwise the default one.
    public func brain(for identity: Identity) -> MemoryFolder? { identity.brain.flatMap(brain(id:)) ?? defaultBrain }
    public var takenBrainIDs: Set<String> { Set(brains.map(\.id)) }
    /// The identities attached to a memory.
    public func identities(using brainID: String) -> [Identity] { identities.filter { brain(for: $0)?.id == brainID } }

    public var primary: Identity? { identities.first { $0.isPrimary } }
    public func identity(slug: String) -> Identity? { identities.first { $0.slug == slug } }
    public var takenSlugs: Set<String> { Set(identities.map(\.slug)) }
}
