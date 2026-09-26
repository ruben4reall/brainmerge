import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct AccountsFilterTests {
    func account(_ name: String, running: Bool = false, created: TimeInterval = 0) -> Account {
        Account(identity: Identity(slug: IdentitySlug.make(from: name), name: name, createdAt: Date(timeIntervalSince1970: created)), isRunning: running)
    }

    @Test func searchIgnoresCaseAndAccents() {
        let list = [account("ClientStudio"), account("Élodie"), account("Work")]
        #expect(AccountsFilter.apply(list, query: "tst").map(\.identity.name) == ["ClientStudio"])
        #expect(AccountsFilter.apply(list, query: "elo").map(\.identity.name) == ["Élodie"])
        #expect(AccountsFilter.apply(list, query: "  ").count == 3)
    }

    @Test func searchFindsTheClaudeCodeEmail() {
        var ruben = account("Ruben"); ruben.codeAccount = ClaudeCodeAccount(email: "Agency@Example.com")
        let list = [ruben, account("Work")]
        #expect(AccountsFilter.apply(list, query: "example").map(\.identity.name) == ["Ruben"])
        #expect(AccountsFilter.apply(list, query: "agency@").map(\.identity.name) == ["Ruben"])
        #expect(AccountsFilter.apply(list, query: "work").map(\.identity.name) == ["Work"])
    }

    /// The cards keep the sidebar's order, whatever runs: an account that opens never swaps places with another one (the
    /// pointer, still where its button was, would land on another card's button).
    @Test func theCardsKeepTheSidebarsOrder() {
        let list = [account("A", created: 1), account("B", running: true, created: 2), account("C", created: 3)]
        #expect(AccountsFilter.apply(list, query: "").map(\.identity.name) == ["A", "B", "C"])
        var opened = list
        opened[2].isRunning = true
        #expect(AccountsFilter.apply(opened, query: "").map(\.identity.name) == ["A", "B", "C"])
        #expect(AccountsFilter.apply(list, query: "", sort: .name).map(\.identity.name) == ["A", "B", "C"])
    }

    @Test func fiftyAccountsFilterInstantly() {
        let list = (1...50).map { account("Account \($0)", created: TimeInterval($0)) }
        let start = Date()
        let hits = AccountsFilter.apply(list, query: "account 4")
        #expect(hits.count == 11)
        #expect(Date().timeIntervalSince(start) < 0.2)   // generous: the suites run in parallel
    }
}
