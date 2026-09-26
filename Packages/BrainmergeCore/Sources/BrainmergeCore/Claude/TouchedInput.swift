import Foundation

/// What the PostToolUse hook takes from what Claude Code sends after an edit: the path of the file written, nothing else.
/// The text written, the tool's answer and the session are skipped without being decoded.
public struct TouchedInput: Decodable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey, CaseIterable { case tool = "tool_input" }
    struct Tool: Decodable, Equatable, Sendable {
        enum CodingKeys: String, CodingKey, CaseIterable { case path = "file_path" }
        let path: String
    }
    public static let readFields: [String] = ["tool_input.file_path"]

    let tool: Tool
    public var filePath: String { tool.path }

    /// Nil for anything that is not an edit naming its file as text.
    public static func decode(_ data: Data) -> TouchedInput? {
        try? JSONDecoder().decode(TouchedInput.self, from: data)
    }
}
