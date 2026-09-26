import Foundation

/// A small list Brainmerge rewrites (projects, accounts, hidden folders, lines that are not secrets).
enum ExistingFile {
    /// The file's bytes, or nil only when it does not exist. Any other failure (permissions, iCloud not ready) throws:
    /// read as empty, the list would be rewritten with only the new entry and everything else lost.
    static func read(_ file: URL) throws -> Data? {
        do { return try Data(contentsOf: file) } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
