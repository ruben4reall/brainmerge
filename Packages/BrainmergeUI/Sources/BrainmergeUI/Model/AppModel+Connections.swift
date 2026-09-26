import Foundation
import BrainmergeCore

/// A line of the edit sheet's browser picker: what it says, and the profile it picks (nil: none).
public struct BrowserOption: Equatable, Hashable, Sendable {
    public let label: String
    public let choice: BrowserChoice?
}

/// Connections, per account: the browser profile that goes with it, and its MCP servers by name. Nothing here reads a
/// login or a value: profile names and server names only (see BrowserProfiles and MCPInventory).
extension AppModel {
    /// The one-line guides of the Connections section.
    nonisolated static func browserGuide(account: String) -> String {
        "Log the Claude extension of this profile into \(account). Each account then has its own browser, with no logging out."
    }
    nonisolated static let connectorsGuide = "Gmail, Calendar and Drive belong to each Claude account: connect the work Gmail in one account and the personal one in another."
    nonisolated static let demoConnectionsSentence = "Brainmerge does not open a browser in a demo."
    nonisolated static let noBrowserSentence = "No Chrome, Arc, Brave or Edge profile was found on this Mac."

    /// Why the Connections section has no browser picker: said once the browsers are read and none has a profile.
    public var noBrowserNote: String? {
        guard let browsers = installedBrowsers, browsers.allSatisfy(\.profiles.isEmpty) else { return nil }
        return Self.noBrowserSentence
    }

    /// What the edit sheet needs before it opens, read off the main thread: the apps made by hand for the account (already
    /// found when the pointer came over its card), and the connections, read only now. The sheet then opens at its full
    /// size, and nothing moves under the pointer afterwards.
    public func prepareEdit(_ slug: String) async -> [ExistingApp] {
        if let known = knownOtherApps(slug) {
            await loadConnections()
            return known
        }
        async let apps = otherApps(opening: slug)
        await loadConnections()
        return await apps
    }

    /// Reads the browsers' profiles and every account's server names, off the main thread.
    public func loadConnections() async {
        let home = paths.home, find = findBrowsers, paths = self.paths
        let identities = accounts.map(\.identity)
        let (browsers, inventories) = await Task.detached(priority: .userInitiated) {
            let inventories = Dictionary(uniqueKeysWithValues: identities.map { identity in
                (identity.slug, MCPInventory.read(profile: identity.surfaces.cli ? CLIProfile(directory: identity.cliProfile(in: paths)) : nil,
                                                  desktopData: identity.surfaces.desktop ? identity.desktopData(in: paths) : nil))
            })
            return (find(home), inventories)
        }.value
        if installedBrowsers != browsers { installedBrowsers = browsers }
        if mcpInventories != inventories { mcpInventories = inventories }
    }

    /// Saves which browser profile goes with the account (nil: none) on the core queue, then shows it. The sheet calls it
    /// on Save (see `apply`), which says the problem when the pick could not be saved.
    func setBrowser(_ slug: String, _ choice: BrowserChoice?) -> Task<UserMessage?, Never> {
        let saved = saveReporting(.browser(slug)) { state in
            state.identities = state.identities.map { identity in
                var identity = identity
                if identity.slug == slug { identity.browser = choice }
                return identity
            }
        }
        return Task {
            let problem = await saved.value
            reload()
            return problem
        }
    }

    /// "None", then every profile of every browser found, then the pick itself when its profile is gone, so the picker
    /// always shows what is saved. Empty until the browsers are read, or when there is nothing to pick.
    public func browserOptions(keeping choice: BrowserChoice?) -> [BrowserOption] {
        guard let browsers = installedBrowsers else { return [] }
        var options = browsers.flatMap { browser in
            browser.profiles.map { BrowserOption(label: "\(browser.browser.displayName) · \($0.name)",
                                                 choice: BrowserChoice(browser: browser.browser, directory: $0.directory)) }
        }
        if let choice, !options.contains(where: { $0.choice == choice }) {
            options.append(BrowserOption(label: "\(choice.browser.displayName) · \(choice.directory) (not found)", choice: choice))
        }
        return options.isEmpty ? [] : [BrowserOption(label: "None", choice: nil)] + options
    }

    /// The picked profile, when that browser and profile are still there.
    func installedProfile(_ choice: BrowserChoice?) -> (InstalledBrowser, BrowserProfile)? {
        guard let choice, let browser = installedBrowsers?.first(where: { $0.browser == choice.browser }),
              let profile = browser.profiles.first(where: { $0.directory == choice.directory }) else { return nil }
        return (browser, profile)
    }

    /// "Open Chrome (Work)", or nil when no profile, or none still there, is picked.
    public func openBrowserLabel(_ choice: BrowserChoice?) -> String? {
        installedProfile(choice).map { "Open \($0.0.browser.displayName) (\($0.1.name))" }
    }

    /// Starts the picked browser in the picked profile.
    public func openBrowser(_ choice: BrowserChoice) {
        guard let target = target(choice) else { return }
        run(BrowserProfiles.command(app: target.0.app, directory: target.1.directory, url: nil))
    }

    /// claude.ai's connectors page in the picked profile, or in the default browser when none is picked.
    public func manageConnectors(_ choice: BrowserChoice?) {
        guard let choice else { return run(BrowserProfiles.defaultBrowserCommand(url: BrowserProfiles.connectorsURL)) }
        guard let target = target(choice) else { return }
        run(BrowserProfiles.command(app: target.0.app, directory: target.1.directory, url: BrowserProfiles.connectorsURL))
    }

    /// The picked profile, or a sentence when it is gone: never another profile or the default browser in its place, as
    /// either may be logged into another account, and a browser asked for a missing profile makes a new empty one.
    /// Nothing before the browsers are read, when a gone profile cannot be told from one not read yet.
    private func target(_ choice: BrowserChoice) -> (InstalledBrowser, BrowserProfile)? {
        guard installedBrowsers != nil else { return nil }
        if let found = installedProfile(choice) { return found }
        message = UserMessage(title: "This browser profile is gone",
                              detail: "\(choice.browser.displayName) no longer has the profile picked for this account. Pick another one.")
        return nil
    }

    private func run(_ command: BrowserProfiles.Command?) {
        guard let command else { return }
        // A capture or a demo never opens the owner's real browser.
        guard !AppLifecycle.isCaptureOrDemo(environment: environment) else {
            message = UserMessage(title: "Nothing opened", detail: Self.demoConnectionsSentence)
            return
        }
        do { try browserRunner(command) } catch { present(error) }
    }

    public func mcpServers(_ slug: String) -> MCPInventory? { mcpInventories[slug] }
    /// The browsers and this account's servers are read: its edit sheet can open without waiting for them.
    public func connectionsKnown(_ slug: String) -> Bool { installedBrowsers != nil && mcpInventories[slug] != nil }

    /// The server names this account has that no other account has.
    public func onlyHere(_ slug: String) -> Set<String> {
        guard let mine = mcpInventories[slug] else { return [] }
        return mine.onlyHere(comparedWith: mcpInventories.filter { $0.key != slug }.map(\.value))
    }
}
