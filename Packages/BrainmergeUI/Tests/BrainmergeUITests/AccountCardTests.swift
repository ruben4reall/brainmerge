import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct AccountCardTests {
    func account(running: Bool, session: Bool, version: ClaudeVersionState = .notApplicable) -> Account {
        Account(identity: Identity(slug: "work", name: "Work"), isRunning: running, hasSession: session, claudeVersion: version)
    }

    @Test func statusLinesSayWhatToDo() {
        #expect(AccountsView.status(of: account(running: false, session: false), memory: 0) == "Not logged in yet")
        #expect(AccountsView.status(of: account(running: true, session: false), memory: 0) == "Open · log in from its window")
        #expect(AccountsView.status(of: account(running: true, session: true), memory: 0) == "Open")
        #expect(AccountsView.status(of: account(running: false, session: true), memory: 0) == "Closed")
        let outdated = ClaudeVersionState.outdated(installed: "2.8000.0", built: "2.7032.0")
        #expect(AccountsView.status(of: account(running: false, session: true, version: outdated), memory: 0) == "Closed · built for Claude 2.7032.0, 2.8000.0 installed")
        #expect(AccountsView.status(of: account(running: true, session: true, version: outdated), memory: 0) == "Open · runs Claude 2.7032.0, 2.8000.0 installed")
    }
}
