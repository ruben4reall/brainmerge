import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct SidebarTests {
    static let outdated = ClaudeVersionState.outdated(installed: "2.8000.0", built: "2.7032.0")

    func account(_ name: String = "Work", primary: Bool = false, desktop: Bool = true, running: Bool = false, session: Bool = true,
                 version: ClaudeVersionState = .notApplicable) -> Account {
        let identity = Identity(slug: name.lowercased(), name: name, isPrimary: primary, surfaces: Surfaces(desktop: desktop))
        return Account(identity: identity, isRunning: running, hasSession: session, claudeVersion: version)
    }

    struct Case {
        let what: String
        let account: Account
        var opening: Set<String> = []
        var busy: Set<String> = []
        var othersOpen = false
        var appExists = true
        let expected: SidebarAccountAction
    }

    var cases: [Case] {
        [
            Case(what: "closed", account: account(), expected: .open),
            Case(what: "closed, the others open", account: account(), othersOpen: true, expected: .open),
            Case(what: "running", account: account(running: true), expected: .show),
            Case(what: "running, not logged in", account: account(running: true, session: false), expected: .show),
            Case(what: "opening", account: account(), opening: ["work"], expected: .opening),
            Case(what: "opening, another one", account: account(), opening: ["client"], expected: .open),
            Case(what: "running and still marked opening", account: account(running: true), opening: ["work"], expected: .show),
            Case(what: "busy", account: account(), busy: ["work"], expected: .updating),
            Case(what: "busy while running", account: account(running: true), busy: ["work"], expected: .updating),
            Case(what: "busy while opening", account: account(), opening: ["work"], busy: ["work"], expected: .updating),
            Case(what: "Claude Code only", account: account(desktop: false, session: false), expected: SidebarAccountAction.none),
            Case(what: "Claude Code only, busy", account: account(desktop: false, session: false), busy: ["work"], expected: SidebarAccountAction.none),
            Case(what: "primary closed", account: account("Ruben", primary: true), appExists: false, expected: .open),
            Case(what: "primary running", account: account("Ruben", primary: true, running: true), appExists: false, expected: .show),
            Case(what: "app missing", account: account(), appExists: false, expected: .rebuild),
            Case(what: "app missing, running", account: account(running: true), appExists: false, expected: .show),
            Case(what: "app missing, being rebuilt", account: account(), busy: ["work"], appExists: false, expected: .updating),
            Case(what: "outdated closed", account: account(version: Self.outdated), expected: .open),
            Case(what: "outdated running", account: account(running: true, version: Self.outdated), expected: .show),
            Case(what: "not logged in, alone", account: account(session: false), expected: .open),
            Case(what: "not logged in, the others open", account: account(session: false), othersOpen: true, expected: .open),
            // Claude missing: nothing runs, versions are not applicable, the click explains that Claude isn't installed.
            Case(what: "Claude missing", account: account(), expected: .open),
            Case(what: "Claude missing, primary", account: account("Ruben", primary: true), appExists: false, expected: .open),
        ]
    }

    func action(_ c: Case) -> SidebarAccountAction {
        SidebarAccountAction.of(account: c.account, opening: c.opening, busy: c.busy, othersOpen: c.othersOpen, appExists: c.appExists)
    }

    @Test func accountLabelNeverLies() {
        for c in cases {
            #expect(action(c) == c.expected, "\(c.what)")
        }
        // The words next to the name: the same vocabulary as the cards, and never "Update" (a click in the sidebar does not update).
        #expect(SidebarAccountAction.open.label == "Open")
        #expect(SidebarAccountAction.show.label == "Show")
        #expect(SidebarAccountAction.opening.label == "Opening…")
        #expect(SidebarAccountAction.updating.label == "Updating…")
        #expect(SidebarAccountAction.rebuild.label == "Rebuild")
        #expect(SidebarAccountAction.none.label == nil)
        // A click does something only when the label promises it.
        #expect(SidebarAccountAction.open.isEnabled && SidebarAccountAction.show.isEnabled && SidebarAccountAction.rebuild.isEnabled)
        #expect(!SidebarAccountAction.opening.isEnabled && !SidebarAccountAction.updating.isEnabled)
        for c in cases {
            let label = action(c).label ?? ""
            #expect(!label.localizedCaseInsensitiveContains("update ") && label != "Update", "\(c.what)")
        }
    }

    @Test func helpSaysWhatAClickDoes() {
        func help(_ c: Case) -> String { action(c).help(for: c.account, othersOpen: c.othersOpen) }
        #expect(help(Case(what: "", account: account(), expected: .open)) == "Open Claude as Work")
        #expect(help(Case(what: "", account: account("Ruben", primary: true), appExists: false, expected: .open)) == "Open Claude as Ruben")
        #expect(help(Case(what: "", account: account(running: true), expected: .show)) == "Show Work's Claude window")
        #expect(help(Case(what: "", account: account(desktop: false, session: false), expected: .none)) == "Claude Code only: this account has no Claude window")
        // Logging in while another account is open: the link would land in the other window. Never an offer to quit it.
        let login = help(Case(what: "", account: account(session: false), othersOpen: true, expected: .open))
        #expect(login == "Opens Claude to log in. Quit your other Claude windows first, so the login lands in this one.")
        #expect(help(Case(what: "", account: account(session: false), expected: .open)) == "Open Claude as Work")
        // An outdated copy still opens: the help says which Claude it was built for.
        let outdated = help(Case(what: "", account: account(version: Self.outdated), expected: .open))
        #expect(outdated.hasPrefix("Open Claude as Work"))
        #expect(outdated.contains("Built for Claude 2.7032.0, 2.8000.0 is installed"))
        #expect(help(Case(what: "", account: account(), appExists: false, expected: .rebuild)).contains("missing"))
        // No dash in anything the sidebar shows or says.
        for c in cases {
            let a = action(c)
            for text in [a.label ?? "", help(c), a.accessibilityLabel(for: c.account)] {
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(c.what): \(text)")
            }
        }
    }

    @Test func helpNamesTheClaudeCodeEmailWhenKnown() {
        var work = account()
        work.codeAccount = ClaudeCodeAccount(email: "alex@example.com", displayName: "Alex")
        #expect(SidebarAccountAction.open.help(for: work, othersOpen: false) == "Open Claude as Work (alex@example.com)")
        // Logging in while others are open: the warning stays as it is.
        var fresh = account(session: false)
        fresh.codeAccount = ClaudeCodeAccount(email: "alex@example.com")
        #expect(SidebarAccountAction.open.help(for: fresh, othersOpen: true).hasPrefix("Opens Claude to log in."))
        // The words next to the name never carry the email.
        #expect(SidebarAccountAction.open.accessibilityLabel(for: work) == "Work, Open")
    }

    @Test func voiceOverReadsTheNameAndTheAction() {
        #expect(SidebarAccountAction.open.accessibilityLabel(for: account()) == "Work, Open")
        #expect(SidebarAccountAction.show.accessibilityLabel(for: account(running: true)) == "Work, Show")
        #expect(SidebarAccountAction.none.accessibilityLabel(for: account(desktop: false)) == "Work")
    }

    @Test func sectionsHaveDigitShortcuts() {
        let digits = RootView.Section.allCases.map(\.digit)
        #expect(digits == ["1", "2", "3", "4"])
        #expect(Set(digits).count == RootView.Section.allCases.count)
    }
}
