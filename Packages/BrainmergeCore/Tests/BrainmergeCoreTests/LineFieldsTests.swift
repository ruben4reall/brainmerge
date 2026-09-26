import Foundation
import Testing
@testable import BrainmergeCore

/// The byte walker over one transcript line: the fields it needs, and never a hang on a broken line.
@Suite struct LineFieldsTests {
    func fields(_ line: String) -> LineFields { LineFields.parse(Data(line.utf8)) }

    @Test func readsTheFieldsOfAWellFormedLine() {
        let f = fields(#"{"cwd": "/Users/r/site", "type": "assistant", "timestamp":"2026-09-24T10:00:00.000Z", "message": {"id": "msg_1", "model": "claude-fable-5-1", "content": [{"type":"text","text":"say \"type\": \"user\" here"}], "usage": {"input_tokens": 3, "cache_creation": {"ephemeral_5m_input_tokens": 9}, "cache_creation_input_tokens": 10, "cache_read_input_tokens": 100, "output_tokens": 42}}}"#)
        #expect(f.type == "assistant" && f.cwd == "/Users/r/site" && f.messageID == "msg_1" && f.model == "claude-fable-5-1")
        #expect(f.hasUsage && f.input == 3 && f.cacheCreation == 10 && f.cacheRead == 100 && f.output == 42)
    }

    @Test func malformedLinesReturnInsteadOfSpinning() {
        // A stray closing bracket used to leave the walker without progress, forever.
        for line in [#"{"a":]}"#, #"{"type":"assistant","x":[1,2],]"#, #"{"usage":}"#, #"{"message":{"usage":{"output_tokens":}}}"#, "{", "", "]"] {
            _ = fields(line)
        }
        #expect(fields(#"{"type":"assistant","x":[1,2],]"#).type == "assistant")
    }

    @Test func aNullUsageIsNotAUsage() {
        let f = fields(#"{"type":"assistant","message":{"id":"msg_2","model":"m","usage":null}}"#)
        #expect(!f.hasUsage)
        #expect(UsageReader.sample(from: f, project: "p") == nil)
    }

    /// Kept strings are unescaped like JSON does, surrogate pairs included; skipped ones are only stepped over, however
    /// long and however escaped (a Write's whole text in a tool input).
    @Test func stringsAreUnescapedOrSkippedCheaply() {
        let f = fields(#"{"cwd": "/Users/r/caf\u00e9 \"q\"\\x\/y\n\ud83e\udd8a", "type": "assistant"}"#)
        #expect(f.cwd == "/Users/r/café \"q\"\\x/y\n🦊" && f.type == "assistant")
        let body = String(repeating: #"line \"quoted\" \\ \n"#, count: 200_000)
        let line = #"{"type": "assistant", "message": {"id": "msg_9", "content": [{"type": "tool_use", "input": {"content": ""# + body + #""}}], "usage": {"output_tokens": 7}}}"#
        let start = Date()
        let big = fields(line)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(big.messageID == "msg_9" && big.output == 7)
    }

}
