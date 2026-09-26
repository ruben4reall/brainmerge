import AppKit
import Foundation
import UniformTypeIdentifiers

/// The memory is a folder of Markdown files, so any notes app that reads files can open it.
/// A few well-known ones are detected; anything else goes through "Other app".
public struct NotesApp: Identifiable, Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    /// Where to get it.
    public let website: URL
    /// Where it is installed, when it is.
    public let location: URL?
    public var id: String { bundleIdentifier }
    public init(name: String, bundleIdentifier: String, website: URL, location: URL? = nil) {
        self.name = name; self.bundleIdentifier = bundleIdentifier; self.website = website; self.location = location
    }
}

/// What opens the memory folder.
public enum NotesTarget: Equatable, Sendable {
    case folder
    case app(NotesApp)
    case custom(URL)

    public var label: String {
        switch self {
        case .folder: return "Open folder"
        case .app(let app): return "Open in \(app.name)"
        case .custom(let url): return "Open in \(url.deletingPathExtension().lastPathComponent)"
        }
    }
}

public enum NotesApps {
    public static let known: [NotesApp] = [
        NotesApp(name: "Obsidian", bundleIdentifier: "md.obsidian", website: URL(string: "https://obsidian.md")!),
        NotesApp(name: "Logseq", bundleIdentifier: "com.electron.logseq", website: URL(string: "https://logseq.com")!),
        NotesApp(name: "iA Writer", bundleIdentifier: "pro.writer.mac", website: URL(string: "https://ia.net/writer")!),
        NotesApp(name: "Typora", bundleIdentifier: "abnerworks.Typora", website: URL(string: "https://typora.io")!),
        NotesApp(name: "VS Code", bundleIdentifier: "com.microsoft.VSCode", website: URL(string: "https://code.visualstudio.com")!),
        NotesApp(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", website: URL(string: "https://cursor.com")!),
        NotesApp(name: "Zed", bundleIdentifier: "dev.zed.Zed", website: URL(string: "https://zed.dev")!),
    ]

    /// Free apps to suggest when nothing is installed.
    public static var suggestions: [NotesApp] { Array(known.prefix(2)) }

    /// The known apps present on this Mac, in the order above, with their location. The lookup is injectable for tests.
    public static func installed(lookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> [NotesApp] {
        known.compactMap { app in
            lookup(app.bundleIdentifier).map { NotesApp(name: app.name, bundleIdentifier: app.bundleIdentifier, website: app.website, location: $0) }
        }
    }

    /// The notes apps on this Mac and the icon of each tile (the folder's, each app's), looked up together once. A tile
    /// never asks macOS for its icon as it draws: LaunchServices and the icons cost the main thread whole frames.
    public struct Found: @unchecked Sendable {
        public let apps: [NotesApp]
        /// By `NotesApps.iconKey`.
        public let icons: [String: NSImage]
        public init(apps: [NotesApp], icons: [String: NSImage]) { self.apps = apps; self.icons = icons }
        public func icon(for target: NotesTarget) -> NSImage? { icons[NotesApps.iconKey(target)] }
    }

    static func iconKey(_ target: NotesTarget) -> String {
        switch target {
        case .folder: return "folder"
        case .app(let app): return "app:" + app.bundleIdentifier
        case .custom(let url): return "path:" + url.path
        }
    }

    /// The apps and their icons, in one pass: off the main thread (see `OnboardingModel.detect`, `NotesAppPicker`).
    public static func find(lookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> Found {
        let apps = installed(lookup: lookup)
        var icons = [iconKey(.folder): icon(for: .folder)]
        for app in apps { icons[iconKey(.app(app))] = icon(for: .app(app)) }
        return Found(apps: apps, icons: icons)
    }

    /// `find()` on a background thread.
    public static func found() async -> Found {
        await Task.detached(priority: .userInitiated) { find() }.value
    }

    /// From the saved setting to a target. A chosen app that is no longer installed falls back to the folder.
    public static func target(for setting: String?, installed: [NotesApp]) -> NotesTarget {
        guard let setting else { return .folder }
        if setting.hasPrefix("path:") { return .custom(URL(fileURLWithPath: String(setting.dropFirst(5)))) }
        if let app = installed.first(where: { $0.bundleIdentifier == setting }) { return .app(app) }
        return .folder
    }

    public static func setting(for target: NotesTarget) -> String? {
        switch target {
        case .folder: return nil
        case .app(let app): return app.bundleIdentifier
        case .custom(let url): return "path:" + url.path
        }
    }

    /// The icon macOS shows for an app or a folder, sized for a tile.
    public static func icon(for target: NotesTarget, side: CGFloat = 40) -> NSImage {
        let image: NSImage
        switch target {
        case .folder: image = NSWorkspace.shared.icon(for: .folder)
        case .app(let app): image = app.location.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
        case .custom(let url): image = NSWorkspace.shared.icon(forFile: url.path)
        }
        image.size = NSSize(width: side, height: side)
        return image
    }

    /// Obsidian's link to a folder or a note. Everything that means something in a query is escaped, so a note named
    /// "Q&A + notes" reaches Obsidian whole.
    public static func obsidianURL(for location: URL) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        guard let encoded = location.path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "obsidian://open?path=\(encoded)")
    }

    /// Opens the folder with the target. Obsidian gets its own URL scheme so the folder becomes a vault;
    /// every other app receives the folder as a document; the folder itself opens in the Finder.
    @MainActor
    public static func open(_ folder: URL, with target: NotesTarget) {
        switch target {
        case .folder:
            NSWorkspace.shared.open(folder)
        case .app(let app):
            if app.bundleIdentifier == "md.obsidian", let url = obsidianURL(for: folder) {
                NSWorkspace.shared.open(url)
            } else if let location = app.location {
                NSWorkspace.shared.open([folder], withApplicationAt: location, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
        case .custom(let location):
            NSWorkspace.shared.open([folder], withApplicationAt: location, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    /// Lets the person pick any application; nil when cancelled.
    @MainActor
    public static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use this app"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
