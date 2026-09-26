import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct LoginFlowTests {
    let personal = LoginFlow.Member(slug: "personal", name: "Personal")
    let client = LoginFlow.Member(slug: "client", name: "Client")
    let work = LoginFlow.Member(slug: "work", name: "Work")

    func flow(sessions: [String: Int] = [:]) -> LoginFlow {
        LoginFlow(target: work, running: [personal, work, client], codeSessions: sessions)
    }

    @Test func itClosesExactlyTheRunningAccountsNeverTheTarget() {
        var f = flow()
        #expect(f.start() == [.quit("personal"), .quit("client")])
        #expect(f.status == "Closing Personal…")
    }

    @Test func theStepsNameTheOthersAndTheirSessions() {
        let f = flow(sessions: ["personal": 1, "client": 2])
        #expect(f.title == "Log in to Work")
        #expect(f.steps == [
            "Brainmerge closes your other Claude windows: Personal, Client. 1 Claude Code session in Personal stops too. 2 Claude Code sessions in Client stop too.",
            "Work opens. Log in there as usual.",
            "Once you are in, reopen the others."])
    }

    @Test func itWaitsForEveryExitBeforeOpening() {
        var f = flow()
        _ = f.start()
        #expect(f.observe(running: ["personal", "client"], connected: false) == [])
        #expect(f.observe(running: ["client"], connected: false) == [])
        #expect(f.status == "Closing Client…")
        #expect(f.observe(running: [], connected: false) == [.open("work")])
        #expect(f.status == "Work is open. Log in in its window.")
        #expect(f.observe(running: ["work"], connected: false) == [])
    }

    @Test func aWindowThatDoesNotCloseIsSaidAfterTenSecondsAndNeverForced() {
        // Claude can ask to confirm the quit: the sheet says so, and quits nothing more.
        let t = Date(timeIntervalSince1970: 1_000)
        var f = flow()
        _ = f.start(now: t)
        #expect(f.observe(running: ["personal"], connected: false, now: t + 9) == [])
        #expect(f.status == "Closing Personal…")
        #expect(f.observe(running: ["personal"], connected: false, now: t + 10) == [])
        #expect(f.status == "Personal is still open. Check its window, or Cancel.")
        #expect(f.closeLabel == "Cancel")
        #expect(f.observe(running: [], connected: false, now: t + 12) == [.open("work")])
        #expect(f.status == "Work is open. Log in in its window.")
    }

    @Test func theReopenButtonWaitsForConnectedOrTheLoggedInClick() {
        var f = flow()
        _ = f.start()
        _ = f.observe(running: [], connected: false)
        #expect(!f.canReopen)
        #expect(f.reopen() == [])
        _ = f.observe(running: ["work"], connected: true)
        #expect(f.canReopen)
        #expect(f.status == "Work is connected.")
        #expect(f.reopenLabel == "Reopen Personal and Client")

        var g = flow()
        _ = g.start(); _ = g.observe(running: [], connected: false)
        g.confirmLoggedIn()
        #expect(g.canReopen)
        #expect(g.reopen() == [.open("personal"), .open("client")])
        #expect(g.reopen() == [])
    }

    @Test func nothingReopensWithoutAClick() {
        var f = flow()
        var effects = f.start()
        effects += f.observe(running: [], connected: false)
        effects += f.observe(running: ["work"], connected: true)
        effects += f.observe(running: ["work"], connected: true)
        #expect(!effects.contains(.open("personal")) && !effects.contains(.open("client")))
    }

    @Test func cancelReopensOnlyWhatItClosed() {
        var before = flow()
        #expect(before.cancel() == [])

        // Client is still closing: it opens again once it has closed, never on top of its exit.
        var closing = flow()
        _ = closing.start()
        _ = closing.observe(running: ["client"], connected: false)
        #expect(closing.cancel() == [.open("personal"), .openOnceClosed("client")])

        var justStarted = flow()
        _ = justStarted.start()
        #expect(justStarted.cancel() == [.openOnceClosed("personal"), .openOnceClosed("client")])

        var opened = flow()
        _ = opened.start(); _ = opened.observe(running: [], connected: false)
        #expect(opened.cancel() == [.open("personal"), .open("client")])
        #expect(opened.cancel() == [])

        var alone = LoginFlow(target: work, running: [], codeSessions: [:])
        #expect(alone.start() == [.open("work")])
        #expect(alone.cancel() == [])
    }

    @Test func anAccountThatAlreadyLooksConnectedMustFlipFirst() {
        // An expired session whose files remain: "connected" from the start proves nothing.
        var f = LoginFlow(target: work, running: [personal], codeSessions: [:], connectedAtStart: true)
        _ = f.start()
        _ = f.observe(running: [], connected: true)
        _ = f.observe(running: ["work"], connected: true)
        #expect(f.step == .opened)
        #expect(!f.canReopen)
        _ = f.observe(running: ["work"], connected: false)
        _ = f.observe(running: ["work"], connected: true)
        #expect(f.step == .connected)
        #expect(f.canReopen)
    }

    @Test func aLoginWithNothingToCloseEndsWithDone() {
        var alone = LoginFlow(target: work, running: [], codeSessions: [:])
        #expect(alone.closeLabel == "Cancel")
        _ = alone.start()
        #expect(alone.closeLabel == "Done")
        #expect(!alone.canConfirm)
        var f = flow()
        _ = f.start()
        _ = f.observe(running: [], connected: false)
        #expect(f.closeLabel == "Cancel")
        #expect(f.canConfirm)
    }

    @Test func theCardShowsLogInWhenItMustAndItsMenuAlways() {
        func account(desktop: Bool = true, session: Bool) -> Account {
            Account(identity: Identity(slug: "work", name: "Work", isPrimary: false, surfaces: Surfaces(desktop: desktop)),
                    isRunning: false, hasSession: session)
        }
        #expect(AccountsView.showsLogInButton(account(session: false), opening: false))
        #expect(!AccountsView.showsLogInButton(account(session: false), opening: true))
        #expect(!AccountsView.showsLogInButton(account(session: true), opening: false))
        // A session that expired can keep its files: the menu still offers it.
        #expect(AccountsView.offersLogIn(account(session: true)))
        #expect(!AccountsView.offersLogIn(account(desktop: false, session: false)))
    }
}
