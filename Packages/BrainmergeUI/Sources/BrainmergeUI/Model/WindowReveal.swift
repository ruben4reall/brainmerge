import Foundation

/// How "Show" brings a running account's window back. Claude keeps running when its window is closed, and bringing the
/// process forward shows no window; opening its app again, as a Dock click does, makes Claude show its window. That
/// reaches the right account only when no other running process shares its app.
enum WindowReveal: Equatable {
    /// Open this app again: macOS brings its running instance forward and Claude shows its window.
    case reopen(URL)
    /// Only bring the process forward: another running process has the same app (the primary and a secondary opened
    /// through its launcher both run Claude's own app), so opening it again could reach the other account.
    case activate

    static func of(pid: Int32, bundle: URL?, running: [(pid: Int32, bundle: URL?)]) -> WindowReveal {
        guard let bundle else { return .activate }
        let key = Self.key(bundle)
        let shared = running.contains { $0.pid != pid && $0.bundle.map(Self.key) == key }
        return shared ? .activate : .reopen(bundle)
    }

    /// Claude itself, a copy of it, or one of Brainmerge's launchers: the only apps "Show" may bring forward.
    static func isClaude(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return id == "com.anthropic.claudefordesktop" || id.hasPrefix("ch.rubencatalao.brainmerge.launch.")
    }

    static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.lowercased()
    }
}
