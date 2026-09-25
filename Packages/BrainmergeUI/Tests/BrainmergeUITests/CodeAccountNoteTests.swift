import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// The lines under Name in the edit sheet: which email Claude Code uses, and the renames offered from it.
@Suite struct CodeAccountNoteTests {
    func account(_ name: String, primary: Bool = false, cli: Bool = true, email: String? = nil, displayName: String? = nil) -> Account {
        let identity = Identity(slug: IdentitySlug.make(from: name), name: name, isPrimary: primary, surfaces: Surfaces(desktop: true, cli: cli))
        return Account(identity: identity, isRunning: false, codeAccount: email.map { ClaudeCodeAccount(email: $0, displayName: displayName) })
    }

    func note(_ account: Account, typed: String? = nil, _ all: [Account]) -> CodeAccountNote? {
        CodeAccountNote.make(for: account, typedName: typed ?? account.identity.name, among: all)
    }

    /// The owner's setup: "Ruben" is logged in with the address named after "Agency", and the reverse.
    @Test func swappedNamesAreOfferedASwap() throws {
        let ruben = account("Ruben", primary: true, email: "agency@example.com", displayName: "Ruben")
        let agency = account("Agency", email: "r.dev@example.com", displayName: "Ruben")
        let all = [ruben, agency]
        let mine = try #require(note(ruben, all))
        #expect(mine.line == "Claude Code uses agency@example.com.")
        #expect(mine.swapWith == CodeAccountNote.Other(slug: "agency", name: "Agency"))
        #expect(mine.swapLine == "This email looks like “Agency”, the name of another account.")
        #expect(mine.swapLabel == "Swap names with Agency")
        // Claude Code's display name is already this account's name: nothing to use.
        #expect(mine.useLabel == nil)
        // On the other account: its address does not look like a name, and "Ruben" is taken.
        let theirs = try #require(note(agency, all))
        #expect(theirs.line == "Claude Code uses r.dev@example.com.")
        #expect(theirs.swapWith == nil && theirs.swapLabel == nil && theirs.swapLine == nil)
        #expect(theirs.useLabel == nil)
    }

    @Test func theAddressIsComparedLettersAndDigitsOnly() {
        let agency = account("Agen Cy")
        let me = account("Ruben", email: "Ag.En-Cy@example.com")
        #expect(note(me, [me, agency])?.swapWith?.slug == agency.id)
        // An address that is this account's own name, even if another name looks the same: no swap.
        let alex = account("Alex", email: "alex@example.com"), other = account("A.lex")
        #expect(note(alex, [alex, other])?.swapWith == nil)
        // An address that matches no account: no swap.
        let solo = account("Work", email: "hello@example.com")
        #expect(note(solo, [solo, account("Client")])?.swapWith == nil)
    }

    /// Two accounts on one Claude account: renaming does not fix that (one of them has to log in with another account),
    /// and a swap would only move the mismatch to the other account. No swap is offered.
    @Test func noSwapWhenBothAccountsUseTheSameEmail() {
        let ruben = account("Ruben", primary: true, email: "agency@example.com")
        let agency = account("Agency", email: "Agency@Example.com")
        #expect(note(ruben, [ruben, agency])?.swapWith == nil)
        // Another account on the same email as this one: still nothing to swap.
        let third = account("Work", email: "agency@example.com")
        let agencyElsewhere = account("Agency", email: "other@example.com")
        #expect(note(ruben, [ruben, agencyElsewhere, third])?.swapWith == nil)
    }

    /// The swap renames both accounts at once, when confirmed: the question says so, and that colors stay.
    @Test func theSwapIsConfirmedFirst() throws {
        let ruben = account("Ruben", primary: true, email: "agency@example.com")
        let agency = account("Agency", email: "ruben@example.com")
        let offer = try #require(note(ruben, [ruben, agency]))
        #expect(offer.swapQuestion(thisName: "Ruben") == "Swap the names of Ruben and Agency?")
        #expect(offer.swapExplanation == "Both accounts are renamed now, not when you save. Colors and photos stay with each account.")
    }

    @Test func theDisplayNameIsOfferedOnlyWhenItDiffersAndIsFree() {
        let work = account("Work", email: "alex@example.com", displayName: "Alex")
        #expect(note(work, [work, account("Client")])?.useLabel == "Use “Alex”")
        #expect(note(work, [work, account("Client")])?.suggestedName == "Alex")
        // Already typed (whatever the case): gone.
        #expect(note(work, typed: "alex ", [work])?.useLabel == nil)
        // Taken by another account: never offered, the name would be refused anyway.
        #expect(note(work, [work, account("ALEX")])?.useLabel == nil)
        // No display name recorded: nothing to offer.
        let bare = account("Work", email: "alex@example.com")
        #expect(note(bare, [bare])?.useLabel == nil)
    }

    @Test func unknownAndOffStates() {
        let fresh = account("Client")
        let unknown = note(fresh, [fresh])
        #expect(unknown?.email == nil)
        // True for an account never logged in and for one logged out alike.
        #expect(unknown?.line == "Claude Code is not logged in with this account.")
        #expect(unknown?.useLabel == nil && unknown?.swapLabel == nil)
        // Claude Code off: the sheet says nothing about it at all.
        let off = account("Desk", cli: false, email: "desk@example.com")
        #expect(note(off, [off]) == nil)
    }

    @Test func thePromiseLineAndNoDashes() {
        #expect(CodeAccountNote.privacy == "Brainmerge reads the email Claude Code shows for this account, never a password or a login token.")
        let ruben = account("Ruben", primary: true, email: "agency@example.com", displayName: "Rubén")
        let agency = account("Agency")
        let texts = [note(ruben, [ruben, agency]), note(agency, [ruben, agency])].compactMap { $0 }
            .flatMap { note in [note.line, note.useLabel, note.swapLine, note.swapLabel, note.swapWith.map { _ in note.swapExplanation }].compactMap { $0 } }
            + [CodeAccountNote.privacy]
        #expect(texts.count >= 5)
        for text in texts { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)") }
    }

    /// An address is never offered as a name: names end up in app names, Claude's instructions and memory commits.
    @Test func anAddressIsNeverOfferedAsAName() {
        let work = account("Work", email: "alex@example.com", displayName: "alex@example.com")
        #expect(note(work, [work])?.suggestedName == nil)
        #expect(note(work, [work])?.useLabel == nil)
        let named = account("Work", email: "alex@example.com", displayName: "Alex")
        #expect(note(named, [named])?.suggestedName == "Alex")
    }
}
