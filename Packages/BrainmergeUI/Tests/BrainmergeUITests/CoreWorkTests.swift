import Foundation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// Core work from the window: one change at a time, a waiting sentence while any remains, accounts at work left alone,
/// and each call reporting its own problem only.
@MainActor @Suite struct CoreWorkTests {
    func model(_ e: ManagerEnv, monitor: ProcessMonitor? = nil) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor)
        return AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
    }

    /// What the work closures did, in order, from any thread.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var entries: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    @Test func coreWorkRunsOneAtATimeInOrder() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        let log = Log()
        let gate = DispatchSemaphore(value: 0)
        let first = Task { await m.perform("First…") { log.add("first started"); gate.wait(); log.add("first done") } }
        try await waitUntil { log.entries.contains("first started") }
        let second = Task { await m.perform("Second…") { log.add("second started") } }
        try await Task.sleep(for: .milliseconds(200))
        // The second change waits: it never reads the state while the first one is still writing it.
        #expect(log.entries == ["first started"])
        gate.signal()
        _ = await first.value
        _ = await second.value
        #expect(log.entries == ["first started", "first done", "second started"])
    }

    @Test func theWaitingSentenceStaysWhileAnyWorkRemains() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        let log = Log()
        let gateA = DispatchSemaphore(value: 0), gateB = DispatchSemaphore(value: 0)
        let a = Task { await m.perform("A…") { log.add("a"); gateA.wait() } }
        try await waitUntil { log.entries.contains("a") }
        let b = Task { await m.perform("B…") { log.add("b"); gateB.wait() } }
        try await waitUntil { m.working != nil && log.entries.count >= 1 }
        #expect(m.working == "A…")
        gateA.signal()
        _ = await a.value
        // A is done, B still runs: Save and Swap stay disabled, and the sentence says what is running now.
        try await waitUntil { log.entries.contains("b") }
        #expect(m.working == "B…")
        gateB.signal()
        _ = await b.value
        #expect(m.working == nil)
    }

    /// An account whose app is being worked on (a swap, a rename) is never rebuilt by the automatic update meanwhile.
    @Test func theAutomaticUpdateLeavesAnAccountAtWorkAlone() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.iconMode = .tintedClone
        _ = try e.manager.add(request)
        _ = try FakeClaudeApp.make(in: e.home.url, version: "2.8000.0")
        let m = model(e)
        m.reload()
        m.markBusy("client", true)
        await m.checkClaudeUpdate()
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.7032.0")
        m.markBusy("client", false)
        await m.checkClaudeUpdate()
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.8000.0")
    }

    /// Two overlapping changes of one account: the first to end does not clear the other's mark.
    @Test func busyMarksAreCounted() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.markBusy("client", true)
        m.markBusy("client", true)
        m.markBusy("client", false)
        #expect(m.busy == ["client"])
        m.markBusy("client", false)
        #expect(m.busy.isEmpty)
    }

    /// Claude is removed first: a launch could never reach `open`, whatever the code under test does.
    @Test func openingAnAccountAtWorkSaysSoInsteadOfLaunching() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try FileManager.default.removeItem(at: e.claude.url)
        let m = model(e)
        m.reload()
        m.markBusy("client", true)
        m.open("client")
        #expect(m.message?.title == "Client is being updated")
        #expect(m.message?.detail == "Brainmerge is working on Client's app. Try again in a moment.")
        #expect(m.opening.isEmpty)
    }

    /// The sheet shows the problem of its own call, never one another part of the app set meanwhile.
    @Test func anEditReportsOnlyItsOwnProblem() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        let other = UserMessage(title: "Claude's signature is broken", detail: "From an automatic update.")
        m.message = other
        var edit = AccountEdit(account: try #require(m.accounts.first { $0.id == "client" }), memory: "shared")
        edit.note = "Work"
        #expect(await m.apply(edit, to: "client") == nil)
        #expect(m.message == other)
        #expect(try e.store.load().identity(slug: "client")?.note == "Work")
        edit.name = "Ruben"
        let failure = try #require(await m.apply(edit, to: "client"))
        #expect(failure.title == "Check the form")
        #expect(m.message == failure)
        m.dismiss(other)
        #expect(m.message == failure)
        m.dismiss(failure)
        #expect(m.message == nil)
    }

    @Test func aSwapReportsItsOwnProblem() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let agency = try e.manager.add(IdentityManager.AddRequest(name: "Agency"))
        let exe = e.claude.executable.path, data = agency.desktopData(in: e.home.paths).path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        let failure = await m.swapNames("ruben", with: "agency")
        #expect(failure?.title == "Agency is open")
        let closed = model(e)
        closed.reload()
        #expect(await closed.swapNames("ruben", with: "agency") == nil)
        #expect(try e.store.load().identities.map(\.name) == ["Agency", "Ruben"])
    }

    /// Every change that rebuilds or removes a closed secondary's app marks it busy while it runs, and only it.
    @Test func everyChangeToASecondarysAppMarksItBusy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        var edit = AccountEdit(account: try #require(m.accounts.first { $0.id == "client" }), memory: "shared")
        edit.note = "Work"
        let changes: [(String, @MainActor () async -> Void)] = [
            ("apply", { _ = await m.apply(edit, to: "client") }),
            ("rename", { await m.rename("client", to: "Studio") }),
            ("tint", { await m.changeTint("client", to: .green) }),
            ("photo", { await m.changeLogo("client", to: nil) }),
            ("note", { await m.changeNote("client", to: "Client work") }),
            ("rebuild", { await m.rebuild("client") }),
            ("remove", { await m.remove("client", deleteData: false) }),
        ]
        for (name, change) in changes {
            let task = Task { await change() }
            for _ in 0..<1000 where m.working == nil { await Task.yield() }
            #expect(m.busy == ["client"], "\(name)")
            await task.value
            #expect(m.busy.isEmpty, "\(name)")
            #expect(m.message == nil, "\(name): \(m.message?.detail ?? "")")
        }
        #expect(try e.store.load().identity(slug: "client") == nil)
    }

    /// A newer "Opening…" is never cleared by the fallback timer of an older click.
    @Test func anOldOpeningTimerLeavesANewerMarkAlone() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.markOpening("client", fallback: .milliseconds(30))
        // An hour: the newer mark must outlive the whole test even on a slow CI runner.
        m.markOpening("client", fallback: .seconds(3600))
        try await Task.sleep(for: .milliseconds(150))
        #expect(m.opening == ["client"])
        m.markOpening("other", fallback: .milliseconds(30))
        try await waitUntil { !m.opening.contains("other") }
        #expect(m.opening == ["client"])
    }

    /// The sidebar's "Rebuild" builds the missing app; "Opening…" and "Updating…" do nothing.
    @Test func theSidebarsWordsDoWhatTheySay() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Client"))
        let m = model(e)
        m.reload()
        await m.perform(.opening, on: "client")
        await m.perform(.updating, on: "client")
        #expect(m.appURL(of: "client") == nil && m.message == nil)
        await m.perform(.rebuild, on: "client")
        #expect(m.appURL(of: "client") == e.home.paths.launcherApp(name: "Client"))
        #expect(m.message == nil)
    }

    /// The emails on the accounts are read again on the minute clock and when the window comes back to the front.
    @Test func theClocksAndTheWindowReadTheEmailsAgain() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let file = e.primaryProfile.accountFile
        func record(_ email: String, at seconds: TimeInterval) throws {
            try Data(#"{"projects":{},"oauthAccount":{"emailAddress":"\#(email)"}}"#.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: file.path)
        }
        try record("alex@example.com", at: 1_700_000_000)
        let m = model(e)
        await m.launch(minimum: .zero)
        #expect(m.accounts.first?.codeAccount?.email == "alex@example.com")
        try record("sam@example.com", at: 1_700_000_100)
        m.onProjectsTick()
        #expect(m.accounts.first?.codeAccount?.email == "sam@example.com")
        try record("kim@example.com", at: 1_700_000_200)
        m.windowBecameActive()
        #expect(m.accounts.first?.codeAccount?.email == "kim@example.com")
    }
}
