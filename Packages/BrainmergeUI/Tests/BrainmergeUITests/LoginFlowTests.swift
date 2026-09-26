import Foundation
import Testing
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

        var closing = flow()
        _ = closing.start()
        _ = closing.observe(running: ["client"], connected: false)
        #expect(closing.cancel() == [.open("personal"), .open("client")])

        var opened = flow()
        _ = opened.start(); _ = opened.observe(running: [], connected: false)
        #expect(opened.cancel() == [.open("personal"), .open("client")])
        #expect(opened.cancel() == [])

        var alone = LoginFlow(target: work, running: [], codeSessions: [:])
        #expect(alone.start() == [.open("work")])
        #expect(alone.cancel() == [])
    }
}
