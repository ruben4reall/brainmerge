import Foundation
import BrainmergeCore

/// Connections, per account: the browser profile that goes with it, and its MCP servers by name. Nothing here reads a
/// login or a value: profile names and server names only (see BrowserProfiles and MCPInventory).
extension AppModel {
    /// The one-line guides of the Connections section.
    nonisolated static func browserGuide(account: String) -> String {
        "Log the Claude extension of this profile into \(account). Each account then has its own browser, with no logging out."
    }
    nonisolated static let connectorsGuide = "Gmail, Calendar and Drive belong to each Claude account: connect the work Gmail in one account and the personal one in another."
    nonisolated static let demoConnectionsSentence = "Brainmerge does not open a browser in a demo."

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

    /// Saves which browser profile goes with the account (nil: none), then shows it.
    @discardableResult
    public func setBrowser(_ slug: String, _ choice: BrowserChoice?) -> Task<Void, Never> {
        let saved = save(.browser(slug)) { state in
            state.identities = state.identities.map { identity in
                var identity = identity
                if identity.slug == slug { identity.browser = choice }
                return identity
            }
        }
        return Task { await saved.value; reload() }
    }

    /// The account's picked profile, when that browser and profile are still there.
    func browserProfile(_ slug: String) -> (InstalledBrowser, BrowserProfile)? {
        guard let choice = accounts.first(where: { $0.id == slug })?.identity.browser,
              let browser = installedBrowsers.first(where: { $0.browser == choice.browser }),
              let profile = browser.profiles.first(where: { $0.directory == choice.directory }) else { return nil }
        return (browser, profile)
    }

    /// "Open Chrome (Work)", or nil when no profile goes with the account.
    public func openBrowserLabel(_ slug: String) -> String? {
        browserProfile(slug).map { "Open \($0.0.browser.displayName) (\($0.1.name))" }
    }

    /// Starts the account's browser in its profile.
    public func openBrowser(_ slug: String) {
        guard let choice = accounts.first(where: { $0.id == slug })?.identity.browser else { return }
        guard let (browser, profile) = browserProfile(slug) else {
            message = UserMessage(title: "This browser profile is gone",
                                  detail: "\(choice.browser.displayName) no longer has the profile picked for this account. Pick another one.")
            return
        }
        run(BrowserProfiles.command(app: browser.app, directory: profile.directory, url: nil))
    }

    /// The account's connectors page on claude.ai, in its profile, or in the default browser when none was picked.
    public func manageConnectors(_ slug: String) {
        if let (browser, profile) = browserProfile(slug) {
            run(BrowserProfiles.command(app: browser.app, directory: profile.directory, url: BrowserProfiles.connectorsURL))
        } else {
            run(BrowserProfiles.defaultBrowserCommand(url: BrowserProfiles.connectorsURL))
        }
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

    /// The server names this account has that no other account has.
    public func onlyHere(_ slug: String) -> Set<String> {
        guard let mine = mcpInventories[slug] else { return [] }
        return mine.onlyHere(comparedWith: mcpInventories.filter { $0.key != slug }.map(\.value))
    }
}
