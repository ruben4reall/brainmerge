import AppKit
import Foundation
import BrainmergeCore

/// Where a declined move is remembered: the app's own defaults, a plain dictionary in tests (never a preferences file).
public protocol DeclineStore: AnyObject {
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: DeclineStore {}

/// "Move to Applications": offered when the app runs from a disk image, Downloads, or the Desktop,
/// never from Applications, a working disk, or a build folder. A decline is remembered.
public enum Installer {
    public struct Failure: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    public static func shouldOfferMove(bundlePath: String, home: String, isReadOnly: Bool) -> Bool {
        if bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/") { return false }
        if bundlePath.contains("/.build/") || bundlePath.contains("/DerivedData/") || bundlePath.contains("/Build/Products/") { return false }
        return isReadOnly || bundlePath.hasPrefix(home + "/Downloads/") || bundlePath.hasPrefix(home + "/Desktop/")
    }

    public static func destination(for bundlePath: String) -> URL {
        URL(fileURLWithPath: "/Applications").appending(path: (bundlePath as NSString).lastPathComponent)
    }

    /// The currently running bundle.
    public static var bundlePath: String { Bundle.main.bundleURL.resolvingSymlinksInPath().path }

    public static func shouldOfferMove() -> Bool {
        shouldOfferMove(bundlePath: bundlePath, home: FileManager.default.homeDirectoryForCurrentUser.path,
                        isReadOnly: CLIInstaller.isOnReadOnlyVolume(bundlePath))
    }

    static let declinedKey = "installer.declined"
    public static func wasDeclined(bundlePath: String = bundlePath, defaults: any DeclineStore = UserDefaults.standard) -> Bool {
        (defaults.stringArray(forKey: declinedKey) ?? []).contains(bundlePath)
    }
    public static func remember(declined bundlePath: String, defaults: any DeclineStore = UserDefaults.standard) {
        var list = defaults.stringArray(forKey: declinedKey) ?? []
        if !list.contains(bundlePath) { list.append(bundlePath) }
        defaults.set(list, forKey: declinedKey)
    }

    /// After an uninstall: the app bundle goes to the Trash when it lives in an Applications folder, then the app quits.
    @MainActor
    public static func trashSelfAndQuit() {
        let bundle = URL(fileURLWithPath: bundlePath)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/") {
            try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        }
        NSApp.terminate(nil)
    }

    /// Never over a copy that is running: an app stripped of its files mid-flight is a crash.
    public static func canReplace(target: URL, running: [URL]) -> Bool {
        !running.contains { $0.standardizedFileURL.path == target.standardizedFileURL.path }
    }

    /// Copies the app into Applications (the old copy goes to the trash, never erased), opens it from there, and only quits
    /// this one if the new one opened successfully. From Downloads or the Desktop, the original also goes to the trash.
    @MainActor
    public static func moveAndRelaunch(onFailure: @escaping @MainActor (Error) -> Void) {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: bundlePath)
        let target = destination(for: bundlePath)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.compactMap(\.bundleURL)
        guard canReplace(target: target, running: running) else {
            onFailure(Failure(description: "Another Brainmerge is open from Applications. Quit it first, then try again."))
            return
        }
        do {
            let staging = URL(fileURLWithPath: "/Applications").appending(path: ".Brainmerge-installing.app")
            if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
            try fm.copyItem(at: source, to: staging)
            if fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: nil) }
            try fm.moveItem(at: staging, to: target)
            let home = fm.homeDirectoryForCurrentUser.path
            if source.path.hasPrefix(home + "/Downloads/") || source.path.hasPrefix(home + "/Desktop/") { try? fm.trashItem(at: source, resultingItemURL: nil) }
        } catch {
            onFailure(Failure(description: "Brainmerge could not copy itself to Applications (\(error.localizedDescription)). Drag it there yourself, then open it from there."))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    onFailure(Failure(description: "The copy is in Applications but macOS did not open it (\(error.localizedDescription)). Open it from there; if macOS stops it, click Open Anyway in System Settings, Privacy & Security."))
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
