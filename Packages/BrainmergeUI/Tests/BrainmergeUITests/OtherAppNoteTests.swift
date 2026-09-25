import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

/// What the edit sheet says about the apps the person made that also open the account: every app listed once, the
/// risk and the advice said once. Brainmerge only tells: it never opens, adopts or trashes those apps.
@Suite struct OtherAppNoteTests {
    let home = URL(fileURLWithPath: "/Users/alex", isDirectory: true)
    let agency = Identity(slug: "agency", name: "Agency", tint: .blue)
    let ruben = Identity(slug: "ruben", name: "Ruben", isPrimary: true)

    func app(_ name: String, in folder: String = "/Users/alex/Applications", copy: Bool = true, version: String? = "2.2553.13") -> ExistingApp {
        ExistingApp(name: name, url: URL(fileURLWithPath: "\(folder)/\(name).app", isDirectory: true), isClaudeCopy: copy,
                    claudeVersion: copy ? version : nil, dataDir: nil, configDir: nil)
    }

    func note(_ apps: [ExistingApp], _ account: Identity? = nil, installed: String? = "2.9939.2", ownIcon: Bool = true) -> OtherAppNote? {
        OtherAppNote.make(apps: apps, account: account ?? agency, installedClaude: installed, home: home, ownIconOn: ownIcon)
    }

    /// The owner's case with one copy: a copy of an older Claude, made by hand, in ~/Applications.
    @Test func anOlderHandMadeCopyIsExplained() throws {
        let one = try #require(note([app("Claude Second")]))
        #expect(one.intro == nil)
        #expect(one.rows.map(\.text) == ["“Claude Second” in ~/Applications also opens this account."])
        #expect(one.warning == "It is a copy of Claude 2.2553.13 made by hand, and Claude 2.9939.2 is installed: an older Claude on the same data can damage it. It also looks exactly like Claude in the Dock.")
        #expect(one.advice == "Use Brainmerge's app for this account, and move “Claude Second” to the Trash yourself once Agency is closed.")
    }

    /// The owner's real case: two copies. Each is listed once with its version, the warning and the advice come once.
    @Test func severalAppsAreListedAndExplainedOnce() throws {
        let both = try #require(note([app("Claude Second"), app("Claude Second (ancienne 1.49585)", version: "1.49585.0")], ownIcon: false))
        #expect(both.intro == "2 apps you made also open this account:")
        #expect(both.rows.map(\.text) == ["“Claude Second” in ~/Applications, Claude 2.2553.13",
                                          "“Claude Second (ancienne 1.49585)” in ~/Applications, Claude 1.49585.0"])
        #expect(both.warning == "They are copies of Claude made by hand, the oldest is Claude 1.49585.0, and Claude 2.9939.2 is installed: an older Claude on the same data can damage it. They also look exactly like Claude in the Dock.")
        // The Dock switch is off: the advice says to turn it on, since Brainmerge's launcher shows Claude's icon too.
        #expect(both.advice == "Use Brainmerge's app for this account with “Own icon in the Dock” turned on, and move these apps to the Trash yourself once Agency is closed.")
    }

    @Test func onlyTheOlderCopiesAreNamedInTheWarning() throws {
        let mixed = try #require(note([app("Claude Now", version: "2.9939.2"), app("Claude Old", version: "1.49585.0"), app("Opener", copy: false)]))
        #expect(mixed.rows.map(\.text) == ["“Claude Now” in ~/Applications, Claude 2.9939.2", "“Claude Old” in ~/Applications, Claude 1.49585.0",
                                           "“Opener” in ~/Applications"])
        #expect(mixed.warning == "“Claude Old” is a copy of Claude 1.49585.0 made by hand, and Claude 2.9939.2 is installed: an older Claude on the same data can damage it. It also looks exactly like Claude in the Dock.")
    }

    @Test func noWarningWithoutAnOlderClaude() throws {
        // Same version as the one installed, no Claude installed, or not a copy of Claude: nothing to warn about.
        #expect(note([app("Copy", version: "2.9939.2")])?.warning == nil)
        #expect(note([app("Copy")], installed: nil)?.warning == nil)
        let wrapper = try #require(note([app("Agency Opener", copy: false)]))
        #expect(wrapper.warning == nil)
        #expect(wrapper.rows.map(\.text) == ["“Agency Opener” in ~/Applications also opens this account."])
        #expect(wrapper.advice == "Use Brainmerge's app for this account, and move “Agency Opener” to the Trash yourself once Agency is closed.")
        #expect(note([]) == nil)
    }

    @Test func theFolderIsNamedAsFinderShowsIt() {
        #expect(note([app("Claude Work", in: "/Applications")], installed: nil)?.rows.first?.text == "“Claude Work” in /Applications also opens this account.")
    }

    /// The primary is Claude itself: the advice is to open it with Claude, not with an app of Brainmerge's.
    @Test func thePrimaryIsOpenedWithClaudeItself() {
        #expect(note([app("My Claude")], ruben, ownIcon: false)?.advice == "Open Ruben with Claude itself, and move “My Claude” to the Trash yourself once Ruben is closed.")
    }

    @Test func noDashes() {
        let notes = [note([app("Claude Second")]), note([app("A"), app("B", version: "1.0.0")], ownIcon: false),
                     note([app("My Claude", in: "/Applications")], ruben)].compactMap { $0 }
        let texts = notes.flatMap { [$0.intro, $0.warning, $0.advice].compactMap { $0 } + $0.rows.map(\.text) }
        #expect(texts.count >= 10)
        for text in texts { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)") }
    }
}
