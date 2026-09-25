import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Connections: the browser profiles a person can give an account, read from each browser's `Local State` by folder id
/// and display name only. The Google address and ids stored next to them never come out.
@Suite struct BrowserProfilesTests {
    static let sentinel = "sentinel-person@example.com"
    static let localState = """
    {"browser":{"last_used":"x"},"profile":{"last_used":"Default","info_cache":{
      "Default":{"name":"Work","user_name":"\(sentinel)","gaia_id":"123","gaia_name":"\(sentinel)","gaia_given_name":"\(sentinel)","avatar_icon":"x"},
      "Profile 2":{"name":"Personal","user_name":"\(sentinel)","is_using_default_name":false},
      "../evil":{"name":"Bad"},
      "Profile 3":{"user_name":"\(sentinel)"}
    }}}
    """

    @Test func keepsFolderAndNameOnly() {
        let profiles = BrowserProfiles.profiles(localState: Data(Self.localState.utf8), browser: .chrome)
        #expect(profiles == [BrowserProfile(browser: .chrome, directory: "Profile 2", name: "Personal"),
                             BrowserProfile(browser: .chrome, directory: "Default", name: "Work")])
        #expect(!"\(profiles)".contains("sentinel"))
    }

    @Test func unreadableStateGivesNoProfiles() {
        #expect(BrowserProfiles.profiles(localState: Data("not json".utf8), browser: .arc).isEmpty)
        #expect(BrowserProfiles.profiles(localState: Data("{\"profile\":3}".utf8), browser: .arc).isEmpty)
    }

    @Test func folderIdsAreChecked() {
        for good in ["Default", "Profile 2", "Guest Profile"] { #expect(BrowserProfiles.isValidDirectory(good)) }
        for bad in ["", "..", "../x", "a/b", "-x", ".hidden", String(repeating: "a", count: 80), "a\nb"] {
            #expect(!BrowserProfiles.isValidDirectory(bad), "\(bad)")
        }
    }

    /// Only a browser whose app says it is that browser, in /Applications or ~/Applications, with a Local State.
    @Test func findsInstalledBrowsers() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = home.url.appending(path: "Applications")
        try Self.makeApp(at: apps.appending(path: "Google Chrome.app"), bundle: "com.google.Chrome")
        try Self.makeApp(at: apps.appending(path: "Arc.app"), bundle: "not.arc")
        try Self.writeState(home.url, "Library/Application Support/Google/Chrome/Local State")
        try Self.writeState(home.url, "Library/Application Support/Arc/User Data/Local State")
        let found = BrowserProfiles.available(home: home.url, applications: [apps])
        #expect(found.map(\.browser) == [.chrome])
        #expect(found.first?.profiles.map(\.directory) == ["Profile 2", "Default"])
        #expect(found.first?.app == apps.appending(path: "Google Chrome.app"))
    }

    @Test func opensTheProfileByAbsolutePath() throws {
        let app = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let command = try #require(BrowserProfiles.command(app: app, directory: "Profile 2", url: nil))
        #expect(command.path == "/usr/bin/open")
        #expect(command.arguments == ["-na", "/Applications/Google Chrome.app", "--args", "--profile-directory=Profile 2"])
        let connectors = try #require(BrowserProfiles.command(app: app, directory: "Default", url: BrowserProfiles.connectorsURL))
        #expect(connectors.arguments.last == "https://claude.ai/customize/connectors")
        #expect(BrowserProfiles.command(app: URL(fileURLWithPath: "/Applications/Google Chrome.app"), directory: "../x", url: nil) == nil)
        #expect(BrowserProfiles.command(app: URL(string: "relative.app")!, directory: "Default", url: nil) == nil)
        #expect(BrowserProfiles.defaultBrowserCommand(url: BrowserProfiles.connectorsURL)
                == BrowserProfiles.Command(path: "/usr/bin/open", arguments: ["https://claude.ai/customize/connectors"]))
    }

    @Test func choiceIsSavedOnTheIdentity() throws {
        var identity = Identity(slug: "work", name: "Work")
        #expect(identity.browser == nil)
        identity.browser = BrowserChoice(browser: .arc, directory: "Profile 2")
        let data = try JSONEncoder().encode(identity)
        #expect(try JSONDecoder().decode(Identity.self, from: data).browser == BrowserChoice(browser: .arc, directory: "Profile 2"))
    }

    static func makeApp(at url: URL, bundle: String) throws {
        let contents = url.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundle], format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
    }

    static func writeState(_ home: URL, _ relative: String) throws {
        let file = home.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(localState.utf8).write(to: file)
    }
}
