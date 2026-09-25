import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct DoctorTests {
    func doctor(_ e: ManagerEnv) -> Doctor {
        Doctor(paths: e.home.paths, store: e.store, claudeAppURL: e.claude.url, cliPath: e.cliPath)
    }

    @Test func healthySetupHasNoErrors() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let findings = doctor(e).run()
        #expect(!findings.hasErrors)
        #expect(findings.contains { $0.title == "Claude.app" && $0.level == .ok && $0.detail.contains("2.7032.0") })
        #expect(findings.contains { $0.title == "Command line" && $0.level == .warning })
    }

    @Test func reportsMissingLauncherHookBlockAndBrokenLink() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Client"))
        try HookInstaller.remove(settingsFile: e.primaryProfile.settingsFile)
        try Data("# sans bloc\n".utf8).write(to: CLIProfile(directory: client.cliProfile(in: e.home.paths)).claudeMD)
        let link = e.primaryProfile.projectsDir.appending(path: ProjectSlug.slug(forPath: e.atelier)).appending(path: "memory")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: e.home.url.appending(path: "gone"))

        let findings = doctor(e).run()
        #expect(findings.hasErrors)
        #expect(findings.contains { $0.title == "Client: launcher" && $0.level == .error })
        #expect(findings.contains { $0.title == "Perso: hook" && $0.level == .warning })
        #expect(findings.contains { $0.title == "Client: CLAUDE.md" && $0.level == .warning })
        #expect(findings.contains { $0.title == "Perso: memory atelier" && $0.level == .error })
    }

    @Test func reportsMissingClaudeAndBrain() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        try FileManager.default.removeItem(at: e.claude.url)
        try FileManager.default.removeItem(at: e.brain.root)
        let findings = doctor(e).run()
        #expect(findings.contains { $0.title == "Claude.app" && $0.level == .error })
        #expect(findings.contains { $0.title == "Memory: Shared" && $0.level == .error })
    }

    @Test func checksThePrimarysOwnApp() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        #expect(!doctor(e).run().contains { $0.title == "Perso: own app" })   // switched off: nothing to check
        _ = try e.manager.update(slug: "perso", name: nil, tint: nil, logo: nil, ownApp: true)
        let app = e.home.paths.launcherApp(name: "Perso")
        #expect(doctor(e).run().contains { $0.title == "Perso: own app" && $0.level == .ok && $0.detail == app.path })

        // It opens another Claude than the one installed: rebuilding it points it back.
        try JSONEncoder().encode(LauncherConfig(openApp: "/Applications/Other.app"))
            .write(to: app.appending(path: "Contents/Resources/brainmerge.json"), options: .atomic)
        let moved = doctor(e).run().first { $0.title == "Perso: own app" }
        #expect(moved?.level == .warning)
        #expect(moved?.detail.contains("brainmerge identity rebuild perso") == true)

        try FileManager.default.removeItem(at: app)
        let missing = doctor(e).run().first { $0.title == "Perso: own app" }
        #expect(missing?.level == .error)
        #expect(missing?.detail == "Missing \(app.path). Run: brainmerge identity rebuild perso")
    }

    @Test func everyMemoryIsChecked() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Perso")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        var request = IdentityManager.AddRequest(name: "Client"); request.brain = "work"
        _ = try e.manager.add(request)
        let findings = doctor(e).run()
        #expect(findings.contains { $0.title == "Memory: Shared" && $0.level == .ok })
        #expect(findings.contains { $0.title == "Memory: Work" && $0.level == .ok && $0.detail.contains(work.path) })
        #expect(findings.contains { $0.title == "Client: CLAUDE.md" && $0.level == .ok })
        try FileManager.default.removeItem(at: work.url)
        let broken = doctor(e).run()
        let finding = broken.first { $0.title == "Memory: Work" }
        #expect(finding?.level == .error)
        // Never "brain init" for a memory that is not the default one: that command moves the default memory.
        #expect(finding?.detail.contains("brain init") == false)
        #expect(finding?.detail.contains("brain forget work") == true)
    }
}
