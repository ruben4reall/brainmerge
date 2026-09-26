import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct RegistriesTests {
    @Test func projectRegistryAssignsUniqueNamesPerMachine() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "projects.json")
        var reg = try ProjectRegistry.load(file)
        #expect(reg.register(preferredName: "atelier", path: "/a/atelier", machineID: "m1") == "atelier")
        #expect(reg.register(preferredName: "atelier", path: "/a/atelier", machineID: "m1") == "atelier")
        #expect(reg.register(preferredName: "atelier", path: "/b/atelier", machineID: "m1") == "atelier-2")
        #expect(reg.register(preferredName: "atelier", path: "/c/atelier", machineID: "m2") == "atelier")
        try reg.save(to: file)
        let loaded = try ProjectRegistry.load(file)
        #expect(loaded == reg)
        #expect(loaded.name(forPath: "/b/atelier", machineID: "m1") == "atelier-2")
    }

    @Test func emptyOrMissingFileLoadsAsEmptyRegistry() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "projects.json")
        try Data("{}\n".utf8).write(to: file)
        #expect(try ProjectRegistry.load(file).projects.isEmpty)
        #expect(try ProjectRegistry.load(home.url.appending(path: "missing.json")).projects.isEmpty)
    }

    @Test func identityRegistryRecordsNameAndTint() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "identities.json")
        var reg = try IdentityRegistry.load(file)
        reg.record(Identity(slug: "client", name: "ClientStudio", tint: .blue))
        try reg.save(to: file)
        #expect(try IdentityRegistry.load(file).identities["client"] == IdentityRegistry.Entry(name: "ClientStudio", tint: "blue"))
    }

    /// On a Mac's usual disk, `memory/Website` and `memory/website` are one folder: two projects never get names that
    /// differ only in letter case, and a name seen from another Mac keeps its spelling.
    @Test func projectNamesThatDifferOnlyInCaseNeverShareAFolder() {
        var registry = ProjectRegistry()
        #expect(registry.register(preferredName: "Website", path: "/a/Website", machineID: "m1") == "Website")
        #expect(registry.register(preferredName: "website", path: "/b/website", machineID: "m1") == "website-2")
        var seen = ProjectRegistry(projects: ["API": .init(paths: ["m2": "/x/API"])])
        #expect(seen.register(preferredName: "api", path: "/y/api", machineID: "m1") == "API")
        #expect(seen.projects.keys.sorted() == ["API"])
    }
}
