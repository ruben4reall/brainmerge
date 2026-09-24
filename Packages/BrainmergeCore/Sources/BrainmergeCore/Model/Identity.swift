import Foundation

public enum Tint: String, Codable, CaseIterable, Sendable {
    case orange, blue, green, purple, pink, red, yellow, gray
}

public enum IconMode: String, Codable, Sendable { case launcher, tintedClone }

public struct Surfaces: Codable, Equatable, Sendable {
    public var desktop: Bool
    public var cli: Bool
    public init(desktop: Bool = true, cli: Bool = true) { self.desktop = desktop; self.cli = cli }
}

public struct Identity: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var slug: String
    public var name: String
    public var tint: Tint
    public var logoPath: String?
    /// A free-form line under the name: "Personal", "Work", a client name.
    public var note: String?
    public var isPrimary: Bool
    public var surfaces: Surfaces
    public var iconMode: IconMode
    public var sharedHistory: Bool
    /// Adopted folders (existing mount); nil = Paths' standard locations.
    public var cliProfilePath: String?
    public var desktopDataPath: String?
    public var builtForClaudeVersion: String?
    public var createdAt: Date
    /// The memory this identity writes to (a MemoryFolder id); nil means the default one.
    public var brain: String?

    public init(id: UUID = UUID(), slug: String, name: String, tint: Tint = .orange, logoPath: String? = nil, note: String? = nil,
                isPrimary: Bool = false, surfaces: Surfaces = Surfaces(), iconMode: IconMode = .launcher,
                sharedHistory: Bool = false, cliProfilePath: String? = nil, desktopDataPath: String? = nil,
                builtForClaudeVersion: String? = nil, createdAt: Date = Date(), brain: String? = nil) {
        self.id = id; self.slug = slug; self.name = name; self.tint = tint; self.logoPath = logoPath; self.note = note
        self.isPrimary = isPrimary; self.surfaces = surfaces; self.iconMode = iconMode
        self.sharedHistory = sharedHistory; self.cliProfilePath = cliProfilePath
        self.desktopDataPath = desktopDataPath; self.builtForClaudeVersion = builtForClaudeVersion
        self.createdAt = createdAt; self.brain = brain
    }

    /// Name usable as a bundle name: macOS forbids "/" and displays ":" as "/".
    public var bundleDisplayName: String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
    public var gitAuthorEmail: String { "\(slug)@brainmerge.local" }

    public func cliProfile(in paths: Paths) -> URL {
        if let p = cliProfilePath { return URL(fileURLWithPath: p, isDirectory: true) }
        return paths.cliProfile(slug: slug, isPrimary: isPrimary)
    }
    public func desktopData(in paths: Paths) -> URL {
        if let p = desktopDataPath { return URL(fileURLWithPath: p, isDirectory: true) }
        return paths.desktopData(slug: slug, isPrimary: isPrimary)
    }
    /// The app that opens this account from the Dock or Launchpad: its launcher or its tinted copy. None for the primary.
    public func appURL(in paths: Paths) -> URL? {
        guard !isPrimary, surfaces.desktop else { return nil }
        return iconMode == .launcher ? paths.launcherApp(name: bundleDisplayName) : paths.tintedClone(name: bundleDisplayName)
    }
}
