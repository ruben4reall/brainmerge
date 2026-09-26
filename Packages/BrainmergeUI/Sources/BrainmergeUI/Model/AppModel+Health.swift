import Foundation
import BrainmergeCore

/// Health inside the app: the doctor's findings in Settings, each with the one button that mends it, a failed save on the
/// account's card and the Memory screen, and the check run once on its own after a macOS or Claude update.
extension AppModel {
    /// What Settings lists: the findings that are not fine.
    public var healthProblems: [Doctor.Finding] { (health ?? []).filter { $0.level != .ok } }

    /// The doctor on this Mac's setup, with what the app knows (where Claude is, where it looks for apps, git).
    var doctor: Doctor {
        Doctor(paths: paths, store: store, claudeAppURL: claudeAppURL, cliPath: manager.cliPath, appFolders: appFolders, git: git)
    }

    /// Runs the doctor off the main thread, within its budget (10 s): a check that takes longer is left to finish on its
    /// own, its findings dropped (`healthTimedOut`). A check asked for while one runs waits for that one. A capture or a demo
    /// never looks at its demo home: everything is in place.
    @discardableResult
    public func checkHealth() async -> [Doctor.Finding]? {
        if let running = healthTask { return await running.value }
        if AppLifecycle.isCaptureOrDemo(environment: environment) {
            health = []
            return []
        }
        let doctor = self.doctor, run = runHealth, budget = healthBudget
        let task = Task { await Self.within(budget) { run(doctor) } }
        healthTask = task
        healthChecking = true
        let found = await task.value
        healthTask = nil
        healthChecking = false
        healthTimedOut = found == nil
        if let found { health = found }
        return found
    }

    /// `work`'s value, or nil once `budget` is over (the work then runs on, and its value is dropped). The work and the
    /// clock run on background queues, not on Swift's few shared threads: the doctor waits on git and other programs, and
    /// a clock queued behind such waits could not end the check on time.
    nonisolated static func within<T: Sendable>(_ budget: Duration, _ work: @escaping @Sendable () -> T) async -> T? {
        let gate = FirstOnly()
        let (seconds, attoseconds) = budget.components
        let deadline = DispatchTime.now() + Double(seconds) + Double(attoseconds) / 1e18
        return await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
                if gate.claim() { done.resume(returning: nil) }
            }
            DispatchQueue.global(qos: .utility).async {
                let value = work()
                if gate.claim() { done.resume(returning: value) }
            }
        }
    }

    /// A finding's button, then the check again. "Choose memory folder" asks for the folder first (see
    /// `chooseMemoryFolder`); Apple's installer runs in its own window, so there is nothing to check again yet.
    public func applyFix(_ fix: Doctor.Fix) async {
        switch fix {
        case .repairLinks: repair()
        case .rebuild(let slug): await rebuild(slug)
        case .installCLI: installCommandLine()
        case .repairHooks: await repairHooks()
        case .chooseMemory: return
        case .installAppleTools: installAppleTools(); return
        }
        await checkHealth()
    }

    /// "Choose memory folder": the folder where this memory lives now, or an empty one where it starts again (see
    /// IdentityManager.relocateBrain). Its accounts follow it; no note is moved.
    public func chooseMemoryFolder(_ brainID: String, at url: URL) async {
        let manager = self.manager, language = self.language
        _ = await perform("Choosing the memory folder…") { try manager.relocateBrain(id: brainID, to: url, language: language) }
        reload()
        refreshMemory()
        await checkHealth()
    }

    public func dismissHealthNote() { healthNote = nil }

    /// After a macOS or Claude update (a version the setup was not checked after), the check runs once on its own and
    /// says one line. The very first look only notes the versions: it is not an update. The versions are noted before the
    /// check runs, so the app looking again meanwhile never runs it twice. Nothing during the guided setup, on a state
    /// that cannot be read, in a capture or a demo.
    func checkAfterUpdate() async {
        guard !checkingAfterUpdate, !needsOnboarding, stateProblem == nil, !AppLifecycle.isCaptureOrDemo(environment: environment),
              let claudeVersion = claude?.version else { return }
        checkingAfterUpdate = true
        defer { checkingAfterUpdate = false }
        let macOS = macOSVersion(), store = self.store
        // On the core queue, like every save of the state: work there that saves the same file never undoes this one.
        let change: VersionChange? = await withCheckedContinuation { done in
            coreQueue.async {
                guard let state = try? store.load(), VersionChange.differs(state, macOS: macOS, claude: claudeVersion) else {
                    done.resume(returning: nil); return
                }
                done.resume(returning: (try? store.update { VersionChange.record(in: &$0, macOS: macOS, claude: claudeVersion) }) ?? nil)
            }
        }
        guard let change, let found = await checkHealth() else { return }
        healthNote = HealthText.afterUpdate(macOS: change.macOS, claude: change.claude, problems: found.filter { $0.level != .ok }.count)
    }

    // MARK: Failed saves

    /// Read on the memory clock: each account's last save (a small file its Stop hook writes), and for one that failed,
    /// when the account last saved in its memory (its history, only then).
    func refreshSaves() {
        let store = SaveStatusStore(paths: paths)
        var statuses: [String: SaveStatus] = [:]
        var saves: [String: Date] = [:]
        for account in accounts {
            guard let status = store.read(slug: account.id) else { continue }
            statuses[account.id] = status
            guard status.outcome == .failed, let folder = brain(of: account.identity) else { continue }
            let memory = Brain(root: folder.url)
            guard gitAvailable, memory.isInitialized, let entries = try? BrainGit(brain: memory, availability: git).log(limit: 200) else { continue }
            saves[account.id] = entries.first { $0.authorEmail == account.identity.gitAuthorEmail }?.date
        }
        if statuses != saveStatuses { saveStatuses = statuses }
        if saves != lastSaves { lastSaves = saves }
    }

    /// The account's latest save failed, and it has not saved in its memory since: that status, else nil.
    public func saveFailure(of slug: String) -> SaveStatus? {
        guard let status = saveStatuses[slug], status.outcome == .failed else { return nil }
        if let saved = lastSaves[slug], saved >= status.date { return nil }
        return status
    }

    /// The card's line: "Last save failed 3 hours ago: the memory was locked by another program."
    public func saveFailureSentence(of slug: String) -> String? {
        saveFailure(of: slug).map { HealthText.failure($0, now: now()) }
    }

    /// The Memory screen's lines: each account of the selected memory whose last save failed, by name.
    public var memorySaveFailures: [String] {
        guard let folder = selectedFolder else { return [] }
        return accounts(using: folder.id).compactMap { account in
            saveFailure(of: account.id).map { HealthText.failure($0, now: now(), account: account.identity.name) }
        }
    }
}

/// The versions of macOS and Claude that changed since the setup was last checked.
struct VersionChange: Equatable, Sendable {
    var macOS: Bool
    var claude: Bool

    /// Whether the state must be written: a version it does not hold yet.
    static func differs(_ state: AppState, macOS: String, claude: String) -> Bool {
        state.lastCheckedMacOS != macOS || state.lastCheckedClaude != claude
    }

    /// Notes both versions; what changed, nil when nothing did or when there was nothing to compare with (the first look).
    static func record(in state: inout AppState, macOS: String, claude: String) -> VersionChange? {
        let change = VersionChange(macOS: state.lastCheckedMacOS.map { $0 != macOS } ?? false,
                                   claude: state.lastCheckedClaude.map { $0 != claude } ?? false)
        state.lastCheckedMacOS = macOS
        state.lastCheckedClaude = claude
        return change.macOS || change.claude ? change : nil
    }
}

/// Lets the first of two racers through (see `AppModel.within`).
private final class FirstOnly: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { if claimed { return false }; claimed = true; return true } }
}

/// Health's words.
public enum HealthText {
    /// The one button of a finding.
    public static func button(_ fix: Doctor.Fix) -> String {
        switch fix {
        case .repairLinks: "Repair links"
        case .rebuild: "Rebuild"
        case .installCLI: "Install command line"
        case .chooseMemory: "Choose memory folder"
        case .repairHooks: "Repair hooks"
        case .installAppleTools: "Install Apple's tools"
        }
    }

    /// Why a save failed, from the closed list of reasons.
    static func reason(_ reason: SaveStatus.Reason?) -> String {
        switch reason ?? .unknown {
        case .locked: "the memory was locked by another program."
        case .gitMissing: "Apple's Command Line Tools are missing."
        case .diskFull: "the disk is full."
        case .notARepository: "the memory folder is missing or is not a git repository."
        case .heldBack: "a note looks like it holds a key."
        case .unknown: "something unexpected stopped it."
        }
    }

    /// "Last save failed 3 hours ago: …", or "Last save of Work failed …" where the account is not otherwise named.
    public static func failure(_ status: SaveStatus, now: Date, account: String? = nil) -> String {
        let when = ago(status.date, now: now)
        let head = account.map { "Last save of \($0) failed \(when)" } ?? "Last save failed \(when)"
        return "\(head): \(reason(status.reason))"
    }

    /// "just now" within a minute (or a date a little ahead of this Mac's clock), else "3 hours ago", in English
    /// whatever the Mac's language.
    static func ago(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The line after the check that an update started.
    public static func afterUpdate(macOS: Bool, claude: Bool, problems: Int) -> String {
        let what = macOS && claude ? "the macOS and Claude updates" : macOS ? "the macOS update" : "the Claude update"
        let result = problems == 0 ? "all good" : problems == 1 ? "1 thing to fix" : "\(problems) things to fix"
        return "Checked after \(what): \(result)."
    }
}
