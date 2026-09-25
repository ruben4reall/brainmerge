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

    /// Two accounts on one Claude account: the status keeps saying open or closed with the memory used, and a small
    /// mark next to the name carries the whole sentence, the other account's name included (a card is too narrow for it).
    @Test func twoAccountsOnOneClaudeAccountAreMarkedWithoutHidingTheStatus() {
        #expect(AccountsView.duplicateHelp(sameAs: "Agency") == "Same Claude account as Agency")
        let size = ByteCountFormatter.string(fromByteCount: 1_300_000_000, countStyle: .memory)
        #expect(AccountsView.status(of: account(running: true, session: true), memory: 1_300_000_000) == "Open · \(size)")
        #expect(AccountsView.status(of: account(running: false, session: true), memory: 0) == "Closed")
    }

    /// The email on the second line is cut in the middle on a narrow card: its tooltip shows it whole.
    @Test func theSecondLineShowsItsWholeTextOnHover() {
        #expect(AccountsView.subtitleHelp(of: account("Ruben", primary: true, email: "ruben@example.com")) == "ruben@example.com")
        #expect(AccountsView.subtitleHelp(of: account("Work", note: "Day job", email: "alex@example.com")) == "Day job")
        #expect(AccountsView.subtitleHelp(of: account("Work")) == nil)
    }

    /// A Claude Code only account has no window: its status says so rather than "Closed", and its card offers no Open.
    @Test func aClaudeCodeOnlyAccountSaysSo() {
        var identity = Identity(slug: "cli", name: "Terminal"); identity.surfaces = Surfaces(desktop: false, cli: true)
        let terminal = Account(identity: identity, isRunning: false, hasSession: false)
        #expect(AccountsView.status(of: terminal, memory: 0) == "Claude Code only")
        #expect(AccountsView.cardButton(for: terminal, action: .none) == nil)
    }

    /// The card's button says what the sidebar says, and is off where the sidebar is (a second click would open twice,
    /// or open a half-built app). Only the card offers "Update" for an outdated copy.
    @Test func theCardsButtonMatchesTheSidebar() {
        let closed = account(running: false, session: true), running = account(running: true, session: true)
        #expect(AccountsView.cardButton(for: closed, action: .open) == .init(label: "Open", run: .open, isEnabled: true, isProminent: true))
        #expect(AccountsView.cardButton(for: running, action: .show) == .init(label: "Show", run: .open, isEnabled: true, isProminent: false))
        #expect(AccountsView.cardButton(for: closed, action: .opening) == .init(label: "Opening…", run: .open, isEnabled: false, isProminent: true))
        #expect(AccountsView.cardButton(for: closed, action: .updating) == .init(label: "Updating…", run: .open, isEnabled: false, isProminent: true))
        #expect(AccountsView.cardButton(for: closed, action: .rebuild) == .init(label: "Rebuild", run: .rebuild, isEnabled: true, isProminent: true))
        let outdated = account(running: false, session: true, version: .outdated(installed: "2.8000.0", built: "2.7032.0"))
        #expect(AccountsView.cardButton(for: outdated, action: .open) == .init(label: "Update", run: .update, isEnabled: true, isProminent: true))
        #expect(AccountsView.cardButton(for: outdated, action: .updating)?.label == "Updating…")
    }
}
