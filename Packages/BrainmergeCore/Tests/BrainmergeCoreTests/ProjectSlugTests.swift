import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ProjectSlugTests {
    @Test func replicatesClaudeCodeRule() {
        #expect(ProjectSlug.slug(forPath: "/Users/ruben/atelier") == "-Users-ruben-atelier")
        #expect(ProjectSlug.slug(forPath: "/Users/ruben/Library/Application Support/x.y")
                == "-Users-ruben-Library-Application-Support-x-y")
        #expect(ProjectSlug.slug(forPath: "/Users/ruben/été") == "-Users-ruben--t-")
    }
    @Test func projectNames() {
        let home = URL(fileURLWithPath: "/Users/ruben", isDirectory: true)
        #expect(ProjectSlug.projectName(forPath: "/Users/ruben", home: home) == "home")
        #expect(ProjectSlug.projectName(forPath: "/Users/ruben/atelier/", home: home) == "atelier")
        #expect(ProjectSlug.projectName(forPath: "/", home: home) == "root")
    }

    @Test func namesFromSlugStripTheHomePrefix() {
        let home = URL(fileURLWithPath: "/Users/ruben", isDirectory: true)
        #expect(ProjectSlug.projectName(forSlug: "-Users-ruben-kayak", home: home) == "kayak")
        #expect(ProjectSlug.projectName(forSlug: "-Users-ruben", home: home) == "home")
        #expect(ProjectSlug.projectName(forSlug: "-private-tmp-x", home: home) == "-private-tmp-x")
    }

    /// Past 200 characters Claude Code cuts a project's folder name and adds a digest: the folder is found by its start,
    /// and a long path whose folder is not there yet is not linked at a name Claude Code never uses.
    @Test func aLongPathFindsTheFolderClaudeCodeMade() throws {
        let home = try TempHome(); defer { home.remove() }
        let projects = home.url.appending(path: "projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let path = "/Users/me/" + String(repeating: "deep/", count: 50) + "app"
        let slug = ProjectSlug.slug(forPath: path)
        #expect(slug.count > ProjectSlug.maxLength)
        #expect(ProjectSlug.folder(forPath: path, in: projects) == nil)
        let made = String(slug.prefix(ProjectSlug.maxLength)) + "-1a2b3c"
        try FileManager.default.createDirectory(at: projects.appending(path: made), withIntermediateDirectories: true)
        #expect(ProjectSlug.folder(forPath: path, in: projects) == made)
        #expect(ProjectSlug.folder(forPath: "/Users/me/app", in: projects) == "-Users-me-app")
    }

}
