import AppKit
import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct QuickOpenerRankingTests {
    func row(_ id: String, _ name: String, note: String? = nil) -> QuickOpenerRow {
        QuickOpenerRow(id: id, name: name, note: note, tint: .blue, action: .open)
    }

    /// The sidebar's order.
    var rows: [QuickOpenerRow] {
        [row("personal", "Personal", note: "Family and side projects"), row("work", "Work", note: "Acme client"),
         row("acme", "Acme client"), row("client", "Client", note: "Big Co"), row("ecole", "École")]
    }

    func ids(_ query: String) -> [String] { QuickOpenerRanking.filter(rows, query: query).map(\.id) }

    @Test func anEmptyQueryKeepsEveryAccountInTheSidebarOrder() {
        #expect(ids("") == ["personal", "work", "acme", "client", "ecole"])
        #expect(ids("   ") == ["personal", "work", "acme", "client", "ecole"])
    }

    /// Name prefix first, then the start of a word in the name, then the note.
    @Test func namePrefixThenWordPrefixThenNote() {
        #expect(ids("cli") == ["client", "acme", "work"])
        #expect(ids("CLI") == ["client", "acme", "work"])
        #expect(ids("acme c") == ["acme", "work"])
        #expect(ids("side") == ["personal"])
    }

    @Test func accentsAndSpacesAroundTheQueryDoNotMatter() {
        #expect(ids("ecole") == ["ecole"])
        #expect(ids("  wo ") == ["work"])
    }

    /// A few letters from the middle of a name are not a match: "ork" is not Work.
    @Test func theMiddleOfAWordIsNoMatch() {
        #expect(ids("wor") == ["work"])
        #expect(ids("ork").isEmpty)
        #expect(ids("zzz").isEmpty)
    }

    @Test func aWordStartsAfterAHyphenOrADot() {
        let rows = [row("a", "Side-project"), row("b", "acme.io")]
        #expect(QuickOpenerRanking.filter(rows, query: "proj").map(\.id) == ["a"])
        #expect(QuickOpenerRanking.filter(rows, query: "io").map(\.id) == ["b"])
    }

    /// Within a tier the sidebar's order stays: never sorted by name.
    @Test func aTierKeepsTheSidebarOrder() {
        let rows = [row("workshop", "Workshop"), row("work", "Work")]
        #expect(QuickOpenerRanking.filter(rows, query: "work").map(\.id) == ["workshop", "work"])
    }

    // MARK: Rows

    func account(_ name: String, note: String? = nil, desktop: Bool = true, running: Bool = false) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, tint: .green, note: note, surfaces: Surfaces(desktop: desktop)),
                isRunning: running, hasSession: true)
    }

    /// Every account, Claude Code only ones included (their usage and memory are there too), with the sidebar's word.
    @Test func rowsCarryTheSidebarWord() {
        let accounts = [account("Ruben", running: true), account("Work", note: "Acme"), account("Code", desktop: false),
                        account("Client"), account("Perso")]
        let rows = QuickOpenerRanking.rows(accounts: accounts, opening: ["client"], busy: ["perso"], appExists: { _ in true })
        #expect(rows.map(\.id) == ["ruben", "work", "code", "client", "perso"])
        #expect(rows.map(\.word) == ["Show", "Open", "Claude Code only", "Opening…", "Updating…"])
        #expect(rows.map(\.note) == [nil, "Acme", nil, nil, nil])
        #expect(rows.map(\.tint) == [.green, .green, .green, .green, .green])
        #expect(rows.map(\.isEnabled) == [true, true, true, false, false])
    }

    /// The note only, never the email Claude Code records: the panel shows over any app, a shared screen included.
    @Test func aRowNeverShowsTheEmail() throws {
        var work = account("Work")
        work.codeAccount = ClaudeCodeAccount(email: "someone@example.com")
        let rows = QuickOpenerRanking.rows(accounts: [work], opening: [], busy: [], appExists: { _ in true })
        let row = try #require(rows.first)
        #expect(row.note == nil)
        #expect(!"\(row)".contains("someone@example.com"))
    }

    // MARK: Selection and keys

    @Test func theSelectionStaysWithinTheRows() {
        #expect(QuickOpenerRanking.moved(0, by: 1, count: 3) == 1)
        #expect(QuickOpenerRanking.moved(2, by: 1, count: 3) == 2)
        #expect(QuickOpenerRanking.moved(0, by: -1, count: 3) == 0)
        #expect(QuickOpenerRanking.moved(5, by: -1, count: 3) == 1)
        #expect(QuickOpenerRanking.moved(0, by: 1, count: 0) == 0)
    }

    /// Return opens or shows, Cmd-Return the memory, Cmd-U the usage, Esc closes, the arrows move. Anything else is
    /// typing in the search field.
    @Test func keysMapToCommands() {
        func command(_ code: UInt16, _ characters: String?, _ modifiers: NSEvent.ModifierFlags = []) -> QuickOpenerCommand? {
            QuickOpenerKeys.command(keyCode: code, characters: characters, modifiers: modifiers)
        }
        #expect(command(36, "\r") == .open)
        #expect(command(76, "\u{3}") == .open)
        #expect(command(36, "\r", .command) == .memory)
        #expect(command(32, "u", .command) == .usage)
        // By the letter, not the key's place: U sits elsewhere on a Dvorak keyboard.
        #expect(command(7, "u", .command) == .usage)
        #expect(command(32, "g", .command) == nil)
        #expect(command(32, "u") == nil)
        #expect(command(53, "\u{1b}") == .close)
        #expect(command(125, nil, [.numericPad, .function]) == .next)
        #expect(command(126, nil, [.numericPad, .function]) == .previous)
        #expect(command(126, nil, [.shift, .numericPad, .function]) == nil)
        #expect(command(36, "\r", [.command, .shift]) == nil)
        #expect(command(0, "a") == nil)
    }
}
