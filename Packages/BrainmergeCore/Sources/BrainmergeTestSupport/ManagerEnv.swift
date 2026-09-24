import Foundation
import BrainmergeCore

/// A complete HOME: fake Claude.app, primary profile with a project, initialized brain, saved state.
public struct ManagerEnv {
    public let home: TempHome
    public let claude: ClaudeApp
    public let store: StateStore
    public let manager: IdentityManager
    public let brain: Brain
    public let primaryProfile: CLIProfile
    public var cliPath: String { home.url.appending(path: ".local/bin/brainmerge").path }
    public var atelier: String { home.url.path + "/atelier" }

    public static func make(withBrain: Bool = true) throws -> ManagerEnv {
        let home = try TempHome()
        let claude = try FakeClaudeApp.make(in: home.url)
        let primary = try CLIProfile.create(at: home.paths.primaryCLIProfile, inheritingFrom: nil)
        try FileManager.default.createDirectory(at: primary.skillsDir, withIntermediateDirectories: true)
        try Data("# Mes règles\n\n- pas de tiret cadratin\n".utf8).write(to: primary.claudeMD)
        let settings = """
        {"model":"opus[1m]","language":"french","hooks":{"Stop":[{"hooks":[{"type":"command","command":"cd vault && git push"}]}]}}
        """
        try Data(settings.utf8).write(to: primary.settingsFile)
        // Like on a real Mac: ~/.claude/.claude.json is a stub, the projects are in ~/.claude.json.
        try Data(#"{"installMethod":"native"}"#.utf8).write(to: primary.directory.appending(path: ".claude.json"))
        let projects: [String: Any] = [home.url.path + "/atelier": [:]]
        try JSONSerialization.data(withJSONObject: ["projects": projects]).write(to: home.url.appending(path: ".claude.json"))
        let store = StateStore(paths: home.paths)
        var state = AppState(machineID: "m1")
        let brain = withBrain
            ? try Brain.initialize(at: home.paths.defaultBrain, language: .en)
            : Brain(root: home.paths.defaultBrain)
        if withBrain { state.brainPath = brain.root.path }
        try store.save(state)
        let manager = IdentityManager(paths: home.paths, store: store, launcherBinary: Products.launcher,
                                      cliPath: home.url.appending(path: ".local/bin/brainmerge").path,
                                      claudeAppURL: claude.url, registerLaunchers: false)
        return ManagerEnv(home: home, claude: claude, store: store, manager: manager, brain: brain, primaryProfile: primary)
    }
}
