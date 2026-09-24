import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct PathsTests {
    @Test func primaryAndSecondaryLocations() throws {
        let home = try TempHome(); defer { home.remove() }
        let p = home.paths
        #expect(p.cliProfile(slug: "client", isPrimary: true).path == home.url.appending(path: ".claude").path)
        #expect(p.cliProfile(slug: "client", isPrimary: false).lastPathComponent == ".claude-client")
        #expect(p.desktopData(slug: "client", isPrimary: false).lastPathComponent == "Claude-client")
        #expect(p.desktopData(slug: "client", isPrimary: true).lastPathComponent == "Claude")
        #expect(p.launcherApp(name: "ClientStudio").path.hasSuffix("Applications/Brainmerge/ClientStudio.app"))
        #expect(p.tintedClone(name: "ClientStudio").lastPathComponent == "ClientStudio (Claude).app")
        #expect(p.stateFile.path.hasSuffix("Library/Application Support/Brainmerge/state.json"))
        #expect(p.defaultBrain.lastPathComponent == "Brain")
    }

    @Test func homeOverrideFromEnvironment() {
        let p = Paths.current(environment: ["BRAINMERGE_HOME": "/tmp/fake-home"])
        #expect(p.home.path == "/tmp/fake-home")
        #expect(Paths.current(environment: [:]).home == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
    }
}
