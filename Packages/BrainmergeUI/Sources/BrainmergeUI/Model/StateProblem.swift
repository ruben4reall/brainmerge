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

    public var detail: String {
        switch self {
        case .tooNew(let version):
            "It was written by a newer Brainmerge (version \(version) of the file). Your accounts, memories and logins are untouched."
        case .damaged:
            "The file is damaged. A copy from before your last change is available."
        }
    }
}
