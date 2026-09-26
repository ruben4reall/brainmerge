import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct MemoryWiringTests {
    struct Env {
        let home: TempHome
        let brain: Brain
        let profile: CLIProfile
        let wiring: MemoryWiring
        var atelier: String { home.url.path + "/atelier" }
        func link(_ path: String) -> URL {
            profile.projectsDir.appending(path: ProjectSlug.slug(forPath: path), directoryHint: .isDirectory).appending(path: "memory")
        }
    }

    func env(profileDir: URL? = nil) throws -> Env {
        let home = try TempHome()
        let brain = try Brain.initialize(at: home.paths.defaultBrain, language: .en)
        let profile = try CLIProfile.create(at: profileDir ?? home.paths.primaryCLIProfile, inheritingFrom: nil)
        let projects: [String: Any] = [home.url.path + "/atelier": [:], home.url.path: [:]]
        let claudeJSON = profileDir == nil ? home.url.appending(path: ".claude.json") : profile.claudeJSON
        try JSONSerialization.data(withJSONObject: ["projects": projects]).write(to: claudeJSON)
        return Env(home: home, brain: brain, profile: profile, wiring: MemoryWiring(brain: brain, paths: home.paths, machineID: "m1"))
    }

    @Test func linksNewProjectsIntoBrainAndIsIdempotent() throws {
        let e = try env(); defer { e.home.remove() }
        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(Set(result.linked) == ["atelier", "home"])
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: e.link(e.atelier).path)
        #expect(dest == e.brain.memoryDir(forProject: "atelier").path)
        #expect(FileManager.default.fileExists(atPath: e.brain.memoryDir(forProject: "home").path))
        let again = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(again.linked.isEmpty && again.adopted.isEmpty)
        #expect(try e.wiring.status(profile: e.profile).allSatisfy { $0.state == .linked })
        #expect(try ProjectRegistry.load(e.brain.projectsFile).name(forPath: e.atelier, machineID: "m1") == "atelier")
    }

    @Test func adoptsExistingMemoryAndRenamesConflicts() throws {
        let e = try env(); defer { e.home.remove() }
        let fm = FileManager.default
        let real = e.link(e.atelier)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("local index\n".utf8).write(to: real.appending(path: "MEMORY.md"))
        try Data("fact\n".utf8).write(to: real.appending(path: "user_role.md"))
        let target = e.brain.memoryDir(forProject: "atelier")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("brain index\n".utf8).write(to: target.appending(path: "MEMORY.md"))

        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.adopted == ["atelier"])
        #expect(result.conflicts == ["MEMORY.perso.md"])
        #expect(try String(contentsOf: target.appending(path: "MEMORY.md"), encoding: .utf8) == "brain index\n")
        #expect(try String(contentsOf: target.appending(path: "MEMORY.perso.md"), encoding: .utf8) == "local index\n")
        #expect(fm.fileExists(atPath: target.appending(path: "user_role.md").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: real.path) == target.path)
    }

    @Test func externalLinkIsLeftAloneAndReported() throws {
        let e = try env(); defer { e.home.remove() }
        let vault = e.home.url.appending(path: "Vault/98 Memoire", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let link = e.link(e.home.url.path)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: vault)
        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.external == ["home -> \(vault.path)"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == vault.path)
        #expect(!FileManager.default.fileExists(atPath: e.brain.memoryDir(forProject: "home").path))
        let status = try e.wiring.status(profile: e.profile)
        #expect(status.first { $0.name == "home" }?.state == .external(vault.path))
    }

    @Test func brokenLinkIsReplaced() throws {
        let e = try env(); defer { e.home.remove() }
        let link = e.link(e.atelier)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: e.home.url.appending(path: "gone"))
        #expect(try MemoryWiring.inspect(link, target: e.brain.memoryDir(forProject: "atelier")) == .broken)
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "atelier").path)
    }

    @Test func twoIdentitiesShareTheSameTarget() throws {
        let e = try env(); defer { e.home.remove() }
        let second = try CLIProfile.create(at: e.home.paths.cliProfile(slug: "client", isPrimary: false), inheritingFrom: nil)
        try FileManager.default.copyItem(at: e.profile.claudeJSON, to: second.claudeJSON)
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        _ = try e.wiring.wire(profile: second, identitySlug: "client")
        let a = try FileManager.default.destinationOfSymbolicLink(atPath: e.link(e.atelier).path)
        let b = try FileManager.default.destinationOfSymbolicLink(
            atPath: second.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory").path)
        #expect(a == b)
    }

    @Test func sessionFolderWithoutKnownPathIsWiredUnderItsSlugName() throws {
        let e = try env(); defer { e.home.remove() }
        let slug = ProjectSlug.slug(forPath: e.home.url.path + "/kayak")
        try FileManager.default.createDirectory(at: e.profile.projectsDir.appending(path: slug), withIntermediateDirectories: true)
        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.linked.contains("kayak"))
        let link = e.profile.projectsDir.appending(path: slug).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "kayak").path)
    }

    @Test func linksIntoAKnownMemoryAreRelinked() throws {
        let e = try env(); defer { e.home.remove() }
        let fm = FileManager.default
        // The project is linked into a first memory; a second memory becomes the target.
        let other = try Brain.initialize(at: e.home.url.appending(path: "Brain-work"), language: .en)
        let previous = other.memoryDir(forProject: "atelier")
        try fm.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("note\n".utf8).write(to: previous.appending(path: "note.md"))
        try fm.createDirectory(at: e.link(e.atelier).deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: e.link(e.atelier), withDestinationURL: previous)
        // A link into a folder Brainmerge does not manage stays as it is.
        let elsewhere = e.home.url.appending(path: "elsewhere", directoryHint: .isDirectory)
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.createDirectory(at: e.link(e.home.url.path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: e.link(e.home.url.path), withDestinationURL: elsewhere)

        let wiring = MemoryWiring(brain: e.brain, paths: e.home.paths, machineID: "m1", knownRoots: [other.root])
        let result = try wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.linked == ["atelier"])
        #expect(result.external == ["home -> \(elsewhere.path)"])
        #expect(try fm.destinationOfSymbolicLink(atPath: e.link(e.atelier).path) == e.brain.memoryDir(forProject: "atelier").path)
        #expect(fm.fileExists(atPath: previous.appending(path: "note.md").path))
        #expect(!fm.fileExists(atPath: e.brain.memoryDir(forProject: "atelier").appending(path: "note.md").path))
    }

    // MARK: One project, at session start

    /// A session started in a folder Claude Code has not recorded yet (Brainmerge closed, the project brand new): its
    /// memory is linked before Claude writes its first note.
    @Test func wireOneLinksAFolderUnknownToClaudeJSON() throws {
        let e = try env(); defer { e.home.remove() }
        let kayak = e.home.url.path + "/kayak"
        let result = try e.wiring.wireOne(projectPath: kayak, profile: e.profile, identitySlug: "perso")
        #expect(result.linked == ["kayak"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: e.link(kayak).path) == e.brain.memoryDir(forProject: "kayak").path)
        #expect(FileManager.default.fileExists(atPath: e.brain.memoryDir(forProject: "kayak").path))
        #expect(try ProjectRegistry.load(e.brain.projectsFile).name(forPath: kayak, machineID: "m1") == "kayak")
        // Only that project: the ones .claude.json lists wait for the full wiring.
        #expect(!FileManager.default.fileExists(atPath: e.link(e.atelier).path))
    }

    @Test func wireOneAdoptsARealFolderWithTheAccountSuffix() throws {
        let e = try env(); defer { e.home.remove() }
        let fm = FileManager.default
        let real = e.link(e.atelier)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("local index\n".utf8).write(to: real.appending(path: "MEMORY.md"))
        let target = e.brain.memoryDir(forProject: "atelier")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("brain index\n".utf8).write(to: target.appending(path: "MEMORY.md"))
        let result = try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso")
        #expect(result.adopted == ["atelier"] && result.conflicts == ["MEMORY.perso.md"])
        #expect(try String(contentsOf: target.appending(path: "MEMORY.perso.md"), encoding: .utf8) == "local index\n")
        #expect(try fm.destinationOfSymbolicLink(atPath: real.path) == target.path)
    }

    /// A session start that adds its project to the memory's project list leaves that change to the account's own save,
    /// never to "You edited". Already linked, nothing is added.
    @Test func wireOneLeavesTheProjectListToTheAccountsSave() throws {
        let e = try env(); defer { e.home.remove() }
        _ = try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso")
        let ledger = TouchedLedger(brain: e.brain, slug: "perso")
        #expect(try ledger.take() == [".brainmerge/projects.json"])
        try ledger.finish(keeping: [])
        _ = try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso")
        #expect(TouchedLedger.claimed(in: e.brain).isEmpty)
    }

    /// The app's pass over the projects `.claude.json` lists credits the list to the account whose projects they are, like
    /// a session start, never to "You edited". Nothing changed, nothing is added.
    @Test func theFullWiringLeavesTheProjectListToTheAccountsSave() throws {
        let e = try env(); defer { e.home.remove() }
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        let ledger = TouchedLedger(brain: e.brain, slug: "perso")
        #expect(try ledger.take() == [".brainmerge/projects.json"])
        try ledger.finish(keeping: [])
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(TouchedLedger.claimed(in: e.brain).isEmpty)
    }

    /// Notes moved in from an account's own memory folder are that account's: its next save commits them, a renamed
    /// duplicate and a subfolder's notes included, never "You edited".
    @Test func adoptedNotesGoToTheAccountsSave() throws {
        let e = try env(); defer { e.home.remove() }
        let fm = FileManager.default
        let real = e.link(e.atelier)
        try fm.createDirectory(at: real.appending(path: "decisions"), withIntermediateDirectories: true)
        try Data("local index\n".utf8).write(to: real.appending(path: "MEMORY.md"))
        try Data("fact\n".utf8).write(to: real.appending(path: "user_role.md"))
        try Data("why\n".utf8).write(to: real.appending(path: "decisions/prices.md"))
        let target = e.brain.memoryDir(forProject: "atelier")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("brain index\n".utf8).write(to: target.appending(path: "MEMORY.md"))

        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(TouchedLedger.claimed(in: e.brain) == [".brainmerge/projects.json", "memory/atelier/MEMORY.perso.md",
                                                       "memory/atelier/user_role.md", "memory/atelier/decisions/prices.md"])
    }

    /// Every session start asks again: a project already linked into this memory, under whatever name, is left exactly
    /// as it is and nothing is written.
    @Test func wireOneIsIdempotentAndWritesNothingWhenLinked() throws {
        let e = try env(); defer { e.home.remove() }
        _ = try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso")
        let registry = try Data(contentsOf: e.brain.projectsFile)
        let stamp = try FileManager.default.attributesOfItem(atPath: e.brain.projectsFile.path)[.modificationDate] as? Date
        #expect(try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso") == MemoryWiring.Result())
        #expect(try Data(contentsOf: e.brain.projectsFile) == registry)
        #expect(try FileManager.default.attributesOfItem(atPath: e.brain.projectsFile.path)[.modificationDate] as? Date == stamp)
        // Linked earlier under its sessions folder's name only: kept, never renamed "kayak-2".
        let kayak = e.home.url.path + "/kayak"
        try FileManager.default.createDirectory(at: e.profile.projectsDir.appending(path: ProjectSlug.slug(forPath: kayak)), withIntermediateDirectories: true)
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(try e.wiring.wireOne(projectPath: kayak, profile: e.profile, identitySlug: "perso") == MemoryWiring.Result())
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: e.link(kayak).path) == e.brain.memoryDir(forProject: "kayak").path)
        #expect(try ProjectRegistry.load(e.brain.projectsFile).projects["kayak-2"] == nil)
    }

    /// A session start linked a folder `.claude.json` does not list yet, then the app's minute pass sees only its sessions
    /// folder: it keeps the one name, never registers a "kayak-2" beside it, and says it is linked.
    @Test func theFullWiringKeepsTheNameASessionStartGave() throws {
        let e = try env(); defer { e.home.remove() }
        let kayak = e.home.url.path + "/kayak"
        _ = try e.wiring.wireOne(projectPath: kayak, profile: e.profile, identitySlug: "perso")
        for _ in 0..<2 {
            let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
            #expect(result.external.isEmpty)
        }
        #expect(try ProjectRegistry.load(e.brain.projectsFile).projects.keys.sorted() == ["atelier", "home", "kayak"])
        let status = try e.wiring.status(profile: e.profile).first { $0.slug == ProjectSlug.slug(forPath: kayak) }
        #expect(status?.name == "kayak" && status?.state == .linked)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: e.link(kayak).path) == e.brain.memoryDir(forProject: "kayak").path)
    }

    /// The first account's wiring knew only the sessions folder; a session then starts there in a second account sharing
    /// the memory, with no link yet: it joins the same folder of notes.
    @Test func aSecondAccountJoinsTheNameTheFirstGaveBySessionsFolder() throws {
        let e = try env(); defer { e.home.remove() }
        let kayak = e.home.url.path + "/kayak"
        try FileManager.default.createDirectory(at: e.profile.projectsDir.appending(path: ProjectSlug.slug(forPath: kayak)), withIntermediateDirectories: true)
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        let second = try CLIProfile.create(at: e.home.paths.cliProfile(slug: "client", isPrimary: false), inheritingFrom: nil)
        let result = try e.wiring.wireOne(projectPath: kayak, profile: second, identitySlug: "client")
        #expect(result.linked == ["kayak"])
        let link = second.projectsDir.appending(path: ProjectSlug.slug(forPath: kayak)).appending(path: "memory")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == e.brain.memoryDir(forProject: "kayak").path)
        #expect(try ProjectRegistry.load(e.brain.projectsFile).projects["kayak-2"] == nil)
    }

    /// Wired first from its sessions folder alone, then `.claude.json` records its path: still the same name.
    @Test func aPathRecordedLaterKeepsTheSessionsFolderName() throws {
        let e = try env(); defer { e.home.remove() }
        let kayak = e.home.url.path + "/kayak"
        try FileManager.default.createDirectory(at: e.profile.projectsDir.appending(path: ProjectSlug.slug(forPath: kayak)), withIntermediateDirectories: true)
        _ = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        let projects: [String: Any] = [e.atelier: [:], e.home.url.path: [:], kayak: [:]]
        try JSONSerialization.data(withJSONObject: ["projects": projects]).write(to: e.home.url.appending(path: ".claude.json"))
        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.external.isEmpty && result.linked.isEmpty)
        #expect(try ProjectRegistry.load(e.brain.projectsFile).projects["kayak-2"] == nil)
        #expect(try e.wiring.status(profile: e.profile).first { $0.path == kayak }?.state == .linked)
    }

    @Test func wireOneLeavesAnExternalLinkAndIgnoresARelativePath() throws {
        let e = try env(); defer { e.home.remove() }
        let vault = e.home.url.appending(path: "Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: e.link(e.atelier).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: e.link(e.atelier), withDestinationURL: vault)
        let result = try e.wiring.wireOne(projectPath: e.atelier, profile: e.profile, identitySlug: "perso")
        #expect(result.external == ["atelier -> \(vault.path)"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: e.link(e.atelier).path) == vault.path)
        for path in ["", "atelier", "../atelier"] {
            #expect(try e.wiring.wireOne(projectPath: path, profile: e.profile, identitySlug: "perso") == MemoryWiring.Result())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.profile.projectsDir.path) == [ProjectSlug.slug(forPath: e.atelier)])
    }

    /// Setting up again after an uninstall adopts real folders holding copies of the memory: a copy never becomes a second
    /// note, and a conflict name already taken gets the next free one instead of failing.
    @Test func adoptingCopiesOfTheMemoryNeverDuplicatesANote() throws {
        let e = try env(); defer { e.home.remove() }
        let fm = FileManager.default
        let target = e.brain.memoryDir(forProject: "atelier")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("index\n".utf8).write(to: target.appending(path: "MEMORY.md"))
        try Data("brain deploy\n".utf8).write(to: target.appending(path: "deploy.md"))
        try Data("old local\n".utf8).write(to: target.appending(path: "deploy.perso.md"))
        let real = e.link(e.atelier)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("index\n".utf8).write(to: real.appending(path: "MEMORY.md"))
        try Data("new local\n".utf8).write(to: real.appending(path: "deploy.md"))
        try Data("old local\n".utf8).write(to: real.appending(path: "deploy.perso.md"))

        let result = try e.wiring.wire(profile: e.profile, identitySlug: "perso")
        #expect(result.conflicts == ["deploy.perso-2.md"])
        #expect(try fm.contentsOfDirectory(atPath: target.path).sorted() == ["MEMORY.md", "deploy.md", "deploy.perso-2.md", "deploy.perso.md"])
        #expect(try String(contentsOf: target.appending(path: "deploy.perso-2.md"), encoding: .utf8) == "new local\n")
        #expect(try String(contentsOf: target.appending(path: "deploy.md"), encoding: .utf8) == "brain deploy\n")
        #expect(try fm.destinationOfSymbolicLink(atPath: real.path) == target.path)
        let ledger = try String(contentsOf: TouchedLedger(brain: e.brain, slug: "perso").file, encoding: .utf8)
        #expect(ledger.contains("memory/atelier/deploy.perso-2.md") && !ledger.contains("MEMORY") && !ledger.contains("deploy.perso.md"))
    }
}
