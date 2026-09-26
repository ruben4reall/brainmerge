import Foundation

public enum BrainmergeError: Error, Equatable, CustomStringConvertible {
    case stateTooNew(Int)
    case stateDamaged
    case gitUnavailable
    case claudeNotSigned(String)
    case claudeAppNotFound(String)
    case invalidPlist(String)
    case invalidJSON(String)
    case identityExists(String)
    case identityNotFound(String)
    case brainNotConfigured
    case brainNotFound(String)
    case lockTimeout
    case shellFailed(command: String, status: Int32, stderr: String)
    case timedOut(command: String)
    case iconFailed(String)
    case profileMissing(String)
    case identityNameTaken(String)
    case identityRunning(String)
    case cliOnReadOnlyVolume(String)
    case cliLinkOccupied(String)
    case brainUnknown(String)
    case brainInUse(String)
    case brainIsDefault
    case brainNameTaken(String)
    case brainNameEmpty
    case brainFolderInUse(String)
    case defaultMemoryInPlace(String)
    case nameInvalid
    case claudeAppTampered(String)
    case primaryIsClaude
    case memoryInsideRepository(String)
    case heldFileUnknown
    case gitOperationUnfinished
    case noteBeingWritten
    case noteNotSaved
    case noteExists(name: String, project: String)
    case unreadableText(String)
    case sharedHistoryNeedsSameMemory

    public var description: String {
        switch self {
        case .stateTooNew(let v): return "state.json was written by a newer Brainmerge (schema \(v)). Update Brainmerge."
        case .stateDamaged: return "state.json can't be read. Open Brainmerge to put back the copy from before your last change, when there is one."
        case .gitUnavailable: return "History needs git. Install Apple's Command Line Tools: xcode-select --install"
        case .claudeNotSigned: return "This copy of Claude is not signed by Anthropic. Brainmerge only opens the official app."
        case .claudeAppNotFound(let p): return "Claude.app not found at \(p). Install Claude Desktop first."
        case .invalidPlist(let p): return "Cannot read property list \(p)."
        case .invalidJSON(let p): return "Cannot read JSON file \(p)."
        case .identityExists(let s): return "An identity with slug \(s) already exists."
        case .identityNotFound(let s): return "No identity with slug \(s)."
        case .brainNotConfigured: return "No brain configured yet. Run: brainmerge brain init"
        case .brainNotFound(let p): return "Brain folder missing at \(p)."
        case .lockTimeout: return "Another Brainmerge process is saving. Try again in a few seconds."
        case .shellFailed(let c, let s, let e): return "Command failed (\(s)): \(c)\n\(e)"
        case .timedOut(let c): return "Command took too long and was stopped: \(c)"
        case .iconFailed(let p): return "Cannot build an icon from \(p)."
        case .profileMissing(let p): return "Claude Code profile missing at \(p)."
        case .identityNameTaken(let n): return "An identity named \(n) already exists. Choose another name."
        case .identityRunning(let s): return "Identity \(s) is running. Quit it first: brainmerge identity quit \(s)"
        case .cliOnReadOnlyVolume(let p): return "Brainmerge runs from a read-only disk (\(p)). Move it to /Applications first."
        case .cliLinkOccupied(let p): return "Something else is installed at \(p). Move it, then try again."
        case .brainUnknown(let id): return "No memory called \(id). Run: brainmerge brain list"
        case .brainInUse(let n): return "The memory \(n) is still used by an account. Attach that account to another memory first."
        case .brainIsDefault: return "The default memory cannot be forgotten."
        case .brainNameTaken(let n): return "A memory named \(n) already exists. Choose another name."
        case .brainNameEmpty: return "Give the memory a name."
        case .brainFolderInUse(let p): return "The folder \(p) is already one of your memories."
        case .defaultMemoryInPlace(let p):
            return "The default memory is at \(p), and brain init never moves it: its projects would keep writing there, unsaved. To move it, move its folder first, then run: brainmerge brain init NEW_FOLDER. For another memory, run: brainmerge brain add --name NAME FOLDER"
        case .nameInvalid: return "Give it a name: one line, letters and numbers, up to \(NameRules.maxLength) characters."
        case .claudeAppTampered(let p): return "The signature of \(p) does not match its files. Reinstall Claude before making a copy of it."
        case .memoryInsideRepository(let top):
            return "This folder is inside another git repository (\(top)). Brainmerge would create a second repository inside it, and that repository's backups would stop covering these notes. Choose the repository's top folder, or a folder outside it."
        case .heldFileUnknown: return "A note looks like it holds a key, but Brainmerge could not tell which one, so this save kept every note back."
        case .gitOperationUnfinished: return "Git is in the middle of a merge, rebase or cherry-pick in this memory. Saves wait until you finish it."
        case .noteBeingWritten: return "This note is being written. Try again in a moment."
        case .noteNotSaved: return "This note has changes that are not saved yet. Try again once they are saved."
        case .noteExists(let name, let project): return "There is already a note called \(name) in \(project)."
        case .unreadableText(let p): return "\(p) is not UTF-8 text, so Brainmerge left it as it is. Save it as UTF-8, then try again."
        case .sharedHistoryNeedsSameMemory: return "A shared conversation history needs the same memory as your first account: otherwise each project's notes would go back and forth between the two memories."
        case .primaryIsClaude: return "The primary account is the Claude app itself: Brainmerge never makes a copy of it. For an app with its color, use --own-app on."
        }
    }
}
