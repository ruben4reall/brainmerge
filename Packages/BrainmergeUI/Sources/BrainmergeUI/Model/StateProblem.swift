import Foundation
import BrainmergeCore

/// Why the list of accounts cannot be read. Shown on its own screen, never as a fresh install.
public enum StateProblem: Equatable, Sendable {
    case damaged
    case tooNew(Int)

    init(_ error: Error) {
        if case BrainmergeError.stateTooNew(let version) = error { self = .tooNew(version) } else { self = .damaged }
    }

    public static let title = "Brainmerge can't read its list of accounts"

    /// The copy from before is named only when it can be put back (see `StateStore.canRestorePrevious`).
    public func detail(canRestore: Bool) -> String {
        switch self {
        case .tooNew(let version):
            "It was written by a newer Brainmerge (version \(version) of the file). Your accounts, memories and logins are untouched."
        case .damaged where canRestore:
            "The file is damaged. A copy from before your last change is available."
        case .damaged:
            "The file is damaged. Your accounts, memories and logins are untouched."
        }
    }
}
