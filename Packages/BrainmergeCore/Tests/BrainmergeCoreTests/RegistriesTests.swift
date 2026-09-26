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

    /// Only a missing file is an empty list. One that cannot be read (permissions, iCloud not ready) or decoded throws, so
    /// nothing rewrites it with one entry: every other project and machine would be lost.
    @Test func unreadableListsThrowAndAreNeverRewritten() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        var reg = ProjectRegistry()
        _ = reg.register(preferredName: "proj", path: "/a/proj", machineID: "m1")
        try reg.save(to: brain.projectsFile)
        try IdentityRegistry(identities: ["perso": .init(name: "Perso", tint: "blue")]).save(to: brain.identitiesFile)
        for file in [brain.projectsFile, brain.identitiesFile] {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        }
        defer {
            for file in [brain.projectsFile, brain.identitiesFile] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
        }
        #expect(throws: (any Error).self) { try ProjectRegistry.load(brain.projectsFile) }
        #expect(throws: (any Error).self) { try IdentityRegistry.load(brain.identitiesFile) }
        let wiring = MemoryWiring(brain: brain, paths: home.paths, machineID: "m1")
        let profile = try CLIProfile.create(at: home.paths.primaryCLIProfile, inheritingFrom: nil)
        #expect(throws: (any Error).self) { try wiring.wireOne(projectPath: home.url.path + "/other", profile: profile, identitySlug: "perso") }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: brain.projectsFile.path)
        #expect(try ProjectRegistry.load(brain.projectsFile) == reg)
        try Data("{\"projects\": 3}".utf8).write(to: brain.projectsFile)
        #expect(throws: (any Error).self) { try ProjectRegistry.load(brain.projectsFile) }
        #expect(try ProjectRegistry.load(home.url.appending(path: "missing.json")).projects.isEmpty)
    }

    /// The hidden folders and the lines you said are not secrets: a list that cannot be read is never replaced by one
    /// holding only the new entry.
    @Test func unreadableTidyAndNotSecretListsAreNeverRewritten() throws {
        let home = try TempHome(); defer { home.remove() }
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        try FileManager.default.createDirectory(at: brain.metaDir, withIntermediateDirectories: true)
        try Data("{\"hashes\": [\"aa\"]}".utf8).write(to: brain.notSecretsFile)
        try Data("not json".utf8).write(to: brain.hiddenFile)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: brain.notSecretsFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: brain.notSecretsFile.path) }
        #expect(throws: (any Error).self) { try NotSecrets.add(LineHash(line: "x"), in: brain) }
        #expect(throws: (any Error).self) { try MemoryTidy.strictHidden(in: brain) }
        #expect(try String(contentsOf: brain.hiddenFile, encoding: .utf8) == "not json")
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
