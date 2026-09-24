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
}
