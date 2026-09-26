import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// What the PostToolUse hook takes from Claude Code: the path of the file an edit wrote, and nothing else.
@Suite struct TouchedInputTests {
    @Test func onlyTheFilesPathIsRead() throws {
        let sent = #"{"session_id":"sentinel-session","transcript_path":"/tmp/sentinel.jsonl","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/Users/r/.claude-work/projects/-x/memory/deploy.md","content":"sentinel-content"},"tool_response":{"filePath":"/y","success":true}}"#
        let input = try #require(TouchedInput.decode(Data(sent.utf8)))
        #expect(input.filePath == "/Users/r/.claude-work/projects/-x/memory/deploy.md")
        #expect(!String(describing: input).contains("sentinel"))
        for malformed in ["", "{oops", "[]", #"{"tool_input":{}}"#, #"{"tool_input":{"file_path":42}}"#, #"{"tool_input":"x"}"#, #"{"file_path":"/x"}"#] {
            #expect(TouchedInput.decode(Data(malformed.utf8)) == nil, "\(malformed)")
        }
    }

    /// Claude Code writes through the account's link (`projects/<slug>/memory` points into the memory): the note is found
    /// in the memory where it really is. A file anywhere else is not the memory's.
    @Test func aPathThroughTheAccountsLinkIsFoundInTheMemory() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let other = try Brain.initialize(at: e.home.url.appending(path: "Brain-work"), language: .en)
        let project = e.primaryProfile.projectsDir.appending(path: "-Users-r-acme", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: e.brain.memoryDir(forProject: "acme"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appending(path: "memory"), withDestinationURL: e.brain.memoryDir(forProject: "acme"))
        let brains = [other, e.brain]

        let written = project.appending(path: "memory/deploy.md").path
        let found = try #require(TouchedLedger.locate(written, in: brains))
        #expect(found.brain == e.brain && found.path == "memory/acme/deploy.md")
        #expect(TouchedLedger.locate(e.brain.memoryDir.appending(path: "acme/sub/n.md").path, in: brains)?.path == "memory/acme/sub/n.md")
        #expect(TouchedLedger.locate(other.memoryDir.appending(path: "k/n.md").path, in: brains)?.brain == other)
        for outside in [e.home.url.appending(path: "atelier/README.md").path, e.brain.brainMD.path, e.brain.root.appending(path: "Daily/x.md").path,
                        e.brain.memoryDir.path, "relative/memory/x.md", e.brain.memoryDir.path + "/a\nb.md"] {
            #expect(TouchedLedger.locate(outside, in: brains) == nil, "\(outside)")
        }
    }
}
