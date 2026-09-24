import Foundation

/// Whether a Claude data folder holds a logged-in session.
///
/// A profile that logged in carries the app's own storage: a `Cookies` database and an `IndexedDB` folder with
/// content. A profile that was only opened has neither. Only the presence of those entries is checked, by name;
/// nothing inside them is ever read: no credential, no token, no cookie value.
public enum DesktopSession {
    public static func hasSession(dataDir: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataDir.appending(path: "Cookies").path) else { return false }
        let indexedDB = dataDir.appending(path: "IndexedDB", directoryHint: .isDirectory)
        guard let entries = try? fm.contentsOfDirectory(atPath: indexedDB.path) else { return false }
        return entries.contains { !$0.hasPrefix(".") }
    }
}
