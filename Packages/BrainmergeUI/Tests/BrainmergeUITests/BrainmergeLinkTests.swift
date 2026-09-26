import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct BrainmergeLinkTests {
    let known: Set<String> = ["work", "ruben"]
    func parse(_ s: String) -> BrainmergeLink.Action? { BrainmergeLink.parse(URL(string: s)!, accounts: known) }

    @Test func validVerbsParse() {
        #expect(parse("brainmerge://open/work") == .open("work"))
        #expect(parse("brainmerge://show/ruben") == .show("ruben"))
        #expect(parse("brainmerge://memory") == .memory(nil))
        #expect(parse("brainmerge://memory/perso") == .memory("perso"))
        #expect(parse("brainmerge://usage") == .usage)
        #expect(parse("brainmerge://settings") == .settings)
    }

    /// Any web page can fire a link: nothing that adds, edits, removes or quits.
    @Test func otherVerbsGiveNil() {
        #expect(parse("brainmerge://remove/work") == nil)
        #expect(parse("brainmerge://quit/work") == nil)
        #expect(parse("brainmerge://add") == nil)
        #expect(parse("https://open/work") == nil)
        #expect(parse("brainmerge://open") == nil)
    }

    @Test func badSlugsGiveNil() {
        #expect(parse("brainmerge://open/..") == nil)
        #expect(parse("brainmerge://open/wo%2Frk") == nil)
        #expect(parse("brainmerge://open/Work") == nil)
        #expect(parse("brainmerge://memory/..") == nil)
    }

    @Test func unknownAccountGivesNil() { #expect(parse("brainmerge://open/client") == nil) }

    @Test func queryAndExtraPartsAreIgnored() {
        #expect(parse("brainmerge://open/work?folder=/etc") == .open("work"))
        #expect(parse("brainmerge://open/work/more") == .open("work"))
        #expect(parse("brainmerge://usage?x=1") == .usage)
    }

    /// A new verb needs a deliberate change here.
    @Test func actionHasExactlyFiveCases() {
        func name(_ a: BrainmergeLink.Action) -> String {
            switch a { case .open: "open"; case .show: "show"; case .memory: "memory"; case .usage: "usage"; case .settings: "settings" }
        }
        #expect(BrainmergeLink.verbs == ["open", "show", "memory", "usage", "settings"])
        #expect(name(.usage) == "usage")
    }

    @Test func sameLinkWithinTwoSecondsIsIgnored() {
        var gate = BrainmergeLink.Gate()
        let t = Date(timeIntervalSince1970: 1000)
        let url = URL(string: "brainmerge://usage")!
        let a = gate.admit(url, at: t)
        let b = gate.admit(url, at: t.addingTimeInterval(1.5))
        let c = gate.admit(URL(string: "brainmerge://settings")!, at: t.addingTimeInterval(1.6))
        let d = gate.admit(url, at: t.addingTimeInterval(4))
        #expect([a, b, c, d] == [true, false, true, true])
    }
}

@Suite struct AccountsMenuTests {
    func account(_ name: String, running: Bool = false, desktop: Bool = true) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, tint: .blue, isPrimary: false, surfaces: Surfaces(desktop: desktop)),
                isRunning: running, hasSession: true)
    }

    @Test func titlesFollowOpenOrShow() {
        let items = AccountsMenu.items(accounts: [account("Work", running: true), account("Perso")], opening: [], busy: [], appExists: { _ in true })
        #expect(items.map(\.title) == ["Show Work", "Open Perso"])
    }

    @Test func shortcutsGoOnlyToTheFirstNine() {
        let accounts = (1...11).map { account("A\($0)") }
        let items = AccountsMenu.items(accounts: accounts, opening: [], busy: [], appExists: { _ in true })
        #expect(items.count == 11)
        #expect(items.prefix(9).map(\.shortcut) == (1...9).map { Character(String($0)) })
        #expect(items.dropFirst(9).allSatisfy { $0.shortcut == nil })
    }

    @Test func quitConfirmationCountsWindowsAndSessions() {
        #expect(AccountsMenu.quitAllTitle(windows: 3) == "Quit 3 Claude windows?")
        #expect(AccountsMenu.quitAllTitle(windows: 1) == "Quit 1 Claude window?")
        #expect(AccountsMenu.quitAllDetail(sessions: 2) == "Claude Code sessions running in them stop too.")
        #expect(AccountsMenu.quitAllDetail(sessions: 0) == nil)
    }
}
