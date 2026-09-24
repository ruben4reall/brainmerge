import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct CLIInstallerTests {
    @Test func embeddedCLIIsFoundOnlyUnderItsExactName() throws {
        let home = try TempHome(); defer { home.remove() }
        let macos = home.url.appending(path: "Brainmerge.app/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let app = macos.appending(path: "Brainmerge")
        try Data("app".utf8).write(to: app)
        // On a case-insensitive disk, "brainmerge" would match "Brainmerge": the app itself.
        #expect(CLIInstaller.embeddedCLI(besideExecutable: app) == nil)
        try Data("cli".utf8).write(to: macos.appending(path: CLIInstaller.embeddedExecutableName))
        let found = try #require(CLIInstaller.embeddedCLI(besideExecutable: app))
        #expect(found.lastPathComponent == "brainmerge-cli")
    }

    @Test func ensureLinkIsIdempotentAndReplacesAStaleLink() throws {
        let home = try TempHome(); defer { home.remove() }
        let target = home.url.appending(path: "tools/brainmerge-cli")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cli".utf8).write(to: target)
        let link = CLIInstaller.link(in: home.paths)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.url.appending(path: "nowhere"))
        try CLIInstaller.ensureLink(paths: home.paths, target: target)
        try CLIInstaller.ensureLink(paths: home.paths, target: target)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.resolvingSymlinksInPath().path)
    }
}

@Suite struct CLILinkPolicyTests {
    func home(withTool name: String) throws -> (TempHome, URL) {
        let home = try TempHome()
        let tool = home.url.appending(path: "tools/\(name)")
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return (home, tool)
    }

    @Test func aValidLinkToAnotherBinaryIsKeptUnlessAsked() throws {
        let (home, a) = try home(withTool: "a"); defer { home.remove() }
        let b = a.deletingLastPathComponent().appending(path: "b")
        try FileManager.default.copyItem(at: a, to: b)
        try CLIInstaller.ensureLink(paths: home.paths, target: a)
        try CLIInstaller.ensureLink(paths: home.paths, target: b)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.link(in: home.paths).path) == a.resolvingSymlinksInPath().path)
        try CLIInstaller.ensureLink(paths: home.paths, target: b, replaceValid: true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.link(in: home.paths).path) == b.resolvingSymlinksInPath().path)
    }

    @Test func aRegularFileAtTheLinkPathIsNeverDeleted() throws {
        let (home, a) = try home(withTool: "a"); defer { home.remove() }
        let link = CLIInstaller.link(in: home.paths)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: link)
        #expect(throws: BrainmergeError.self) { try CLIInstaller.ensureLink(paths: home.paths, target: a, replaceValid: true) }
        #expect(try String(contentsOf: link, encoding: .utf8) == "mine")
    }

    @Test func aTargetOnAReadOnlyVolumeIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        // /bin/ls lives on the sealed, read-only system volume: the case of an app launched from a DMG.
        #expect(throws: BrainmergeError.self) { try CLIInstaller.ensureLink(paths: home.paths, target: URL(fileURLWithPath: "/bin/ls")) }
        #expect(!FileManager.default.fileExists(atPath: CLIInstaller.link(in: home.paths).path))
    }
}

@Suite struct CurrentExecutableTests {
    @Test func currentExecutableIsTheRunningBinary() throws {
        let url = try #require(CLIInstaller.currentExecutable())
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        #expect(url.path.hasPrefix("/"))
        // Not Bundle.main's value inside an app bundle: the path comes from the kernel (_NSGetExecutablePath).
        #expect(url.lastPathComponent == URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().lastPathComponent)
    }
}
