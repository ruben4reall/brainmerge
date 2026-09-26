import Foundation

/// Logging an account in while the others are closed, as a state machine the app drives: the browser's login link
/// opens in whichever Claude runs, so the target must be alone. It returns what to quit or open and never does it,
/// never touches the browser, the link, the keychain or typing, and reopens the others only on a click.
public struct LoginFlow: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public let slug: String
        public let name: String
        public init(slug: String, name: String) { self.slug = slug; self.name = name }
    }

    /// `openOnceClosed`: reopen a window asked to close as soon as it has exited, never on top of its exit.
    public enum Effect: Equatable, Sendable { case quit(String), open(String), openOnceClosed(String) }

    public enum Step: Equatable, Sendable { case ready, closing, opened, connected, finished }

    public let target: Member
    /// The other accounts open when the sheet appeared: the ones it closes, and later reopens.
    public let others: [Member]
    let codeSessions: [String: Int]
    public private(set) var step: Step = .ready
    /// Asked to close, and not reopened yet.
    private var closed: [Member] = []
    private var stillRunning: [Member] = []
    private var closingSince: Date?
    /// Asked to close 10 s ago and still open: Claude can be asking to confirm the quit. Said, never forced.
    private var slowToClose = false
    private var confirmed = false
    /// The target was seen without a session: from then on, a session means it logged in.
    private var sawDisconnected: Bool

    /// `connectedAtStart`: the target already looked connected (an expired session keeps its files), so only a
    /// session that goes and comes back counts as a login.
    public init(target: Member, running: [Member], codeSessions: [String: Int], connectedAtStart: Bool = false) {
        self.target = target
        self.others = running.filter { $0.slug != target.slug }
        self.codeSessions = codeSessions
        self.sawDisconnected = !connectedAtStart
    }

    public var title: String { "Log in to \(target.name)" }

    public var steps: [String] {
        var first = others.isEmpty ? "No other Claude window is open." : "Brainmerge closes your other Claude windows: \(others.map(\.name).joined(separator: ", "))."
        for member in others {
            guard let n = codeSessions[member.slug], n > 0 else { continue }
            first += n == 1 ? " 1 Claude Code session in \(member.name) stops too." : " \(n) Claude Code sessions in \(member.name) stop too."
        }
        return [first, "\(target.name) opens. Log in there as usual.", "Once you are in, reopen the others."]
    }

    public var status: String? {
        switch step {
        case .ready, .finished: return nil
        case .closing: return stillRunning.first.map { slowToClose ? "\($0.name) is still open. Check its window, or Cancel." : "Closing \($0.name)…" }
        case .opened: return "\(target.name) is open. Log in in its window."
        case .connected: return "\(target.name) is connected."
        }
    }

    public var canReopen: Bool { (step == .connected || (step == .opened && confirmed)) && !closed.isEmpty }
    public var reopenLabel: String { "Reopen \(Self.list(closed.map(\.name)))" }
    /// Shown while waiting for the login, for a connection the file names did not show.
    public var canConfirm: Bool { step == .opened && !confirmed && !others.isEmpty }
    /// The button that ends the sheet: nothing to reopen once it has started alone, so it is done.
    public var closeLabel: String { step != .ready && others.isEmpty ? "Done" : "Cancel" }

    public mutating func start(now: Date = Date()) -> [Effect] {
        guard step == .ready else { return [] }
        if others.isEmpty { step = .opened; return [.open(target.slug)] }
        step = .closing
        closingSince = now
        closed = others
        stillRunning = others
        return others.map { .quit($0.slug) }
    }

    /// Each reload's view: which accounts run, and whether the target now holds a session.
    public mutating func observe(running: Set<String>, connected: Bool, now: Date = Date()) -> [Effect] {
        switch step {
        case .closing:
            stillRunning = stillRunning.filter { running.contains($0.slug) }
            guard stillRunning.isEmpty else {
                if let closingSince, now.timeIntervalSince(closingSince) >= 10 { slowToClose = true }
                return []
            }
            step = .opened
            return [.open(target.slug)]
        case .opened:
            if !connected { sawDisconnected = true } else if sawDisconnected { step = .connected }
            return []
        default: return []
        }
    }

    public mutating func confirmLoggedIn() { if step == .opened { confirmed = true } }

    public mutating func reopen() -> [Effect] {
        guard canReopen else { return [] }
        defer { closed = []; step = .finished }
        return closed.map { .open($0.slug) }
    }

    /// At any step: reopens only what it closed, nothing when it closed nothing; a window still closing opens again
    /// once it has exited.
    public mutating func cancel() -> [Effect] {
        defer { closed = []; stillRunning = []; step = .finished }
        return closed.map { member in stillRunning.contains(member) ? .openOnceClosed(member.slug) : .open(member.slug) }
    }

    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}
