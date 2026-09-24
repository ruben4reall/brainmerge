import Foundation

public struct StateStore: Sendable {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }

    public func load() throws -> AppState {
        let file = paths.stateFile
        guard FileManager.default.fileExists(atPath: file.path) else { return AppState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var state = try decoder.decode(AppState.self, from: Data(contentsOf: file))
        if state.schemaVersion > AppState.currentSchema { throw BrainmergeError.stateTooNew(state.schemaVersion) }
        state.schemaVersion = AppState.currentSchema
        return state
    }

    /// Atomic write: Foundation writes a temporary file then renames it.
    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: paths.stateFile, options: .atomic)
    }
}
