import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// What the edit sheet promises before a save: only a secondary's app is rebuilt, so only a secondary has to be closed.
@Suite struct EditAccountSheetTests {
    func account(_ name: String, primary: Bool = false, running: Bool) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, isPrimary: primary), isRunning: running)
    }

    @Test func theHeaderSaysWhetherTheAccountMustBeClosed() {
        #expect(EditAccountSheet.header(for: account("Ruben", primary: true, running: true)) == "Changes apply when you save. Claude stays open.")
        #expect(EditAccountSheet.header(for: account("Ruben", primary: true, running: false)) == "Changes apply when you save.")
        #expect(EditAccountSheet.header(for: account("Work", running: true)) == "Quit this account first: its app is rebuilt when you save.")
        #expect(EditAccountSheet.header(for: account("Work", running: false)) == "Changes apply when you save.")
    }

    @Test func thePrimarysAppSectionNamesTheAccountAndSaysClaudeIsNeverChanged() {
        let text = EditAccountSheet.ownAppText(name: "Ruben")
        #expect(text == "Ruben is the Claude app itself. Brainmerge never changes Claude, so while it runs the Dock shows Claude's icon. With this switch, Brainmerge adds an app with this color or photo that opens Ruben: keep it in the Dock in place of Claude.")
        #expect(EditAccountSheet.ownAppText(name: "Agency").hasPrefix("Agency is the Claude app itself."))
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
    }

    @Test func theSwitchStartsFromTheSavedChoice() {
        var identity = Identity(slug: "ruben", name: "Ruben", isPrimary: true)
        #expect(!AccountEdit(account: Account(identity: identity, isRunning: false), memory: "shared").ownApp)
        identity.ownApp = true
        #expect(AccountEdit(account: Account(identity: identity, isRunning: false), memory: "shared").ownApp)
    }
}
