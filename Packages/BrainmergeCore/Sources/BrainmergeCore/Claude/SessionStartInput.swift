import Foundation

/// What the SessionStart hook takes from the session Claude Code sends on its input: the folder the session runs in,
/// nothing else. Every other field is skipped without being decoded.
public struct SessionStartInput: Decodable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey, CaseIterable { case cwd }
    public static let readFields: [String] = CodingKeys.allCases.map(\.stringValue)

    public let cwd: String

    /// Nil for anything that is not an object with the folder as text.
    public static func decode(_ data: Data) -> SessionStartInput? {
        try? JSONDecoder().decode(SessionStartInput.self, from: data)
    }
}
