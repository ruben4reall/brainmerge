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

    func account(_ name: String, primary: Bool = false, note: String? = nil, email: String? = nil) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, note: note, isPrimary: primary), isRunning: false,
                codeAccount: email.map { ClaudeCodeAccount(email: $0) })
    }

    @Test func theSecondLineShowsTheClaudeCodeEmailWhenThereIsNoNote() {
        #expect(AccountsView.subtitle(of: account("Ruben", primary: true, email: "ruben@example.com")) == "ruben@example.com")
        #expect(AccountsView.subtitle(of: account("Ruben", primary: true)) == "Primary")
        #expect(AccountsView.subtitle(of: account("Work")) == "Account")
        // A note the person wrote comes first; the email then shows on the name's tooltip.
        let noted = account("Work", note: "Day job", email: "alex@example.com")
        #expect(AccountsView.subtitle(of: noted) == "Day job")
        #expect(AccountsView.nameHelp(of: noted) == "Claude Code is logged in as alex@example.com")
        #expect(AccountsView.nameHelp(of: account("Work", note: "Day job")) == nil)
        #expect(AccountsView.nameHelp(of: account("Work", email: "alex@example.com")) == nil)
    }

    @Test func twoAccountsOnOneClaudeAccountAreSaid() {
        let work = account(running: false, session: true)
        #expect(AccountsView.status(of: work, memory: 0, sameAs: "Ruben") == "Same Claude account as Ruben")
        #expect(AccountsView.status(of: account(running: true, session: true), memory: 0, sameAs: "Ruben") == "Same Claude account as Ruben")
        // What asks for an action keeps its place.
        #expect(AccountsView.status(of: account(running: false, session: false), memory: 0, sameAs: "Ruben") == "Not logged in yet")
        let outdated = ClaudeVersionState.outdated(installed: "2.8000.0", built: "2.7032.0")
        #expect(AccountsView.status(of: account(running: false, session: true, version: outdated), memory: 0, sameAs: "Ruben").hasPrefix("Closed · built for"))
    }
}
