import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// What the edit sheet says about an app the person made that also opens the account. Brainmerge only tells:
/// it never opens, adopts or trashes that app.
@Suite struct OtherAppNoteTests {
    let home = URL(fileURLWithPath: "/Users/alex", isDirectory: true)
    let agency = Identity(slug: "agency", name: "Agency", tint: .blue)
    let ruben = Identity(slug: "ruben", name: "Ruben", isPrimary: true)

    func app(_ name: String, in folder: String = "/Users/alex/Applications", copy: Bool = true, version: String? = "2.2553.13") -> ExistingApp {
        ExistingApp(name: name, url: URL(fileURLWithPath: "\(folder)/\(name).app", isDirectory: true), isClaudeCopy: copy,
                    claudeVersion: copy ? version : nil, dataDir: nil, configDir: nil)
    }

    /// The owner's case: a copy of an older Claude, made by hand, in ~/Applications.
    @Test func anOlderHandMadeCopyIsExplained() {
        let note = OtherAppNote.make(app: app("Claude Second"), account: agency, installedClaude: "2.9939.2", home: home)
        #expect(note.line == "Claude Second (in ~/Applications) also opens this account.")
        #expect(note.warning == "It is a copy of Claude 2.2553.13 made by hand, and Claude 2.9939.2 is installed: an older Claude on the same data can damage it. It also looks exactly like Claude in the Dock.")
        #expect(note.advice == "Use Brainmerge's app for this account, and move Claude Second to the Trash yourself once Agency is closed.")
    }

    @Test func noWarningWithoutAnOlderClaude() {
        // Same version as the one installed, no Claude installed, or not a copy of Claude: nothing to warn about.
        #expect(OtherAppNote.make(app: app("Copy", version: "2.9939.2"), account: agency, installedClaude: "2.9939.2", home: home).warning == nil)
        #expect(OtherAppNote.make(app: app("Copy"), account: agency, installedClaude: nil, home: home).warning == nil)
        let wrapper = OtherAppNote.make(app: app("Agency Opener", copy: false), account: agency, installedClaude: "2.9939.2", home: home)
        #expect(wrapper.warning == nil)
        #expect(wrapper.line == "Agency Opener (in ~/Applications) also opens this account.")
        #expect(wrapper.advice == "Use Brainmerge's app for this account, and move Agency Opener to the Trash yourself once Agency is closed.")
    }

    @Test func theFolderIsNamedAsFinderShowsIt() {
        let system = OtherAppNote.make(app: app("Claude Work", in: "/Applications"), account: agency, installedClaude: nil, home: home)
        #expect(system.line == "Claude Work (in /Applications) also opens this account.")
    }

    /// The primary is Claude itself: the advice is to open it with Claude, not with an app of Brainmerge's.
    @Test func thePrimaryIsOpenedWithClaudeItself() {
        let note = OtherAppNote.make(app: app("My Claude"), account: ruben, installedClaude: "2.9939.2", home: home)
        #expect(note.advice == "Open Ruben with Claude itself, and move My Claude to the Trash yourself once Ruben is closed.")
    }

    @Test func noDashes() {
        let notes = [OtherAppNote.make(app: app("Claude Second"), account: agency, installedClaude: "2.9939.2", home: home),
                     OtherAppNote.make(app: app("My Claude", in: "/Applications"), account: ruben, installedClaude: "2.9939.2", home: home)]
        let texts = notes.flatMap { [$0.line, $0.warning, $0.advice].compactMap { $0 } }
        #expect(texts.count == 6)
        for text in texts { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)") }
    }
}
