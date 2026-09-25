import Foundation
import BrainmergeCore

/// What the edit sheet says about the apps the person made that also open the account (see ExistingApps): each app
/// once, where it is and which Claude it runs, then the risk of an older Claude and what to do, said once for all of
/// them. Brainmerge only tells: it never opens, adopts, re-signs or trashes those apps, the person retires them.
public struct OtherAppNote: Equatable, Sendable {
    /// One detected app, with its own "Show in Finder".
    public struct Row: Equatable, Sendable, Identifiable {
        public let app: ExistingApp
        public let text: String
        public var id: String { app.url.path }
    }

    /// "2 apps you made also open this account:" above several rows; nil for one app, whose row is the whole sentence.
    public let intro: String?
    public let rows: [Row]
    /// Only when a copy of a Claude older than the one installed is among them.
    public let warning: String?
    public let advice: String

    /// Nil when no app was found. `ownIconOn`: the account's "Own icon in the Dock" switch as it stands in the sheet.
    public static func make(apps: [ExistingApp], account: Identity, installedClaude: String?, home: URL, ownIconOn: Bool) -> OtherAppNote? {
        guard !apps.isEmpty else { return nil }
        let single = apps.count == 1
        let rows = apps.map { app -> Row in
            let place = "“\(app.name)” in \(folderLabel(of: app.url, home: home))"
            if single { return Row(app: app, text: "\(place) also opens this account.") }
            return Row(app: app, text: app.claudeVersion.map { "\(place), Claude \($0)" } ?? place)
        }
        var warning: String?
        let older = installedClaude.map { installed in apps.filter { $0.runsOlderClaude(than: installed) } } ?? []
        if let installed = installedClaude, !older.isEmpty {
            let risk = "and Claude \(installed) is installed: an older Claude on the same data can damage it."
            if older.count == 1, let version = older[0].claudeVersion {
                let subject = single ? "It" : "“\(older[0].name)”"
                warning = "\(subject) is a copy of Claude \(version) made by hand, \(risk) It also looks exactly like Claude in the Dock."
            } else {
                let oldest = older.compactMap(\.claudeVersion).min { $0.compare($1, options: .numeric) == .orderedAscending } ?? ""
                let subject = older.count == apps.count ? "They" : names(older)
                warning = "\(subject) are copies of Claude made by hand, the oldest is Claude \(oldest), \(risk) They also look exactly like Claude in the Dock."
            }
        }
        let target = single ? "“\(apps[0].name)”" : "these apps"
        // The primary is Claude itself: it has no app of Brainmerge's to use instead, only an optional opener of Claude.
        // A secondary's launcher shows Claude's icon while it runs: only its own icon tells it apart in the Dock.
        let use = account.isPrimary ? "Open \(account.name) with Claude itself"
            : ownIconOn ? "Use Brainmerge's app for this account" : "Use Brainmerge's app for this account with “Own icon in the Dock” turned on"
        let advice = "\(use), and move \(target) to the Trash yourself once \(account.name) is closed."
        return OtherAppNote(intro: single ? nil : "\(apps.count) apps you made also open this account:", rows: rows, warning: warning, advice: advice)
    }

    /// "“A”", "“A” and “B”", "“A”, “B” and “C”".
    static func names(_ apps: [ExistingApp]) -> String {
        let quoted = apps.map { "“\($0.name)”" }
        guard quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " and " + quoted[quoted.count - 1]
    }

    /// The app's folder as Finder shows it: "~/Applications" in the home folder, the full path elsewhere.
    static func folderLabel(of app: URL, home: URL) -> String {
        let folder = app.deletingLastPathComponent().standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if folder == homePath { return "~" }
        return folder.hasPrefix(homePath + "/") ? "~" + folder.dropFirst(homePath.count) : folder
    }
}
