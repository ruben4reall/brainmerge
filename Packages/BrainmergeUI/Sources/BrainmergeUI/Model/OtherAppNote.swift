import Foundation
import BrainmergeCore

/// What the edit sheet says about an app the person made that also opens the account (see ExistingApps): where it is,
/// the risk when it is a copy of an older Claude, and what to do. Brainmerge only tells: it never opens, adopts,
/// re-signs or trashes that app, the person retires it.
public struct OtherAppNote: Equatable, Sendable, Identifiable {
    public let app: ExistingApp
    /// "<App> (in ~/Applications) also opens this account."
    public let line: String
    /// Only for a copy of a Claude older than the one installed.
    public let warning: String?
    public let advice: String
    public var id: String { app.url.path }

    public static func make(app: ExistingApp, account: Identity, installedClaude: String?, home: URL) -> OtherAppNote {
        let line = "\(app.name) (in \(folderLabel(of: app.url, home: home))) also opens this account."
        var warning: String?
        if let installed = installedClaude, app.runsOlderClaude(than: installed), let old = app.claudeVersion {
            warning = "It is a copy of Claude \(old) made by hand, and Claude \(installed) is installed: an older Claude on the same data can damage it. It also looks exactly like Claude in the Dock."
        }
        // The primary is Claude itself: it has no app of Brainmerge's to use instead, only an optional opener of Claude.
        let use = account.isPrimary ? "Open \(account.name) with Claude itself" : "Use Brainmerge's app for this account"
        let advice = "\(use), and move \(app.name) to the Trash yourself once \(account.name) is closed."
        return OtherAppNote(app: app, line: line, warning: warning, advice: advice)
    }

    /// The app's folder as Finder shows it: "~/Applications" in the home folder, the full path elsewhere.
    static func folderLabel(of app: URL, home: URL) -> String {
        let folder = app.deletingLastPathComponent().standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if folder == homePath { return "~" }
        return folder.hasPrefix(homePath + "/") ? "~" + folder.dropFirst(homePath.count) : folder
    }
}
