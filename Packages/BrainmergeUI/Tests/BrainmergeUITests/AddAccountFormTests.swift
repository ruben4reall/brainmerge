import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct AddAccountFormTests {
    @Test func validation() {
        var form = AddAccountForm()
        #expect(form.validate(existing: []) == "Give this account a name.")
        form.name = "  Client "
        #expect(form.validate(existing: [Identity(slug: "client", name: "client")]) == "There is already an account called Client. Pick another name.")
        #expect(form.validate(existing: []) == nil)
    }

    /// A shared history with another memory would make the two memories fight over the same project links.
    @Test func sharedHistoryNeedsTheSharedMemory() {
        var form = AddAccountForm(); form.name = "Client"; form.sharedHistory = true
        #expect(form.validate(existing: []) == nil)
        form.memory = .own
        #expect(form.validate(existing: []) == "A shared conversation history needs the memory shared with your other accounts. Turn one of them off.")
        form.memory = .existing("work")
        #expect(form.validate(existing: []) != nil)
    }
    @Test func requestCarriesEveryField() {
        var form = AddAccountForm()
        form.name = " Client Studio "; form.tint = .purple; form.note = "Client"; form.sharedHistory = true; form.distinctIcon = true
        form.adoptCLI = URL(fileURLWithPath: "/tmp/cli"); form.adoptDesktop = URL(fileURLWithPath: "/tmp/data")
        let r = form.request
        #expect(r.name == "Client Studio" && r.tint == .purple && r.note == "Client" && r.sharedHistory && r.iconMode == .tintedClone)
        #expect(r.adoptCLIProfile?.path == "/tmp/cli" && r.adoptDesktopData?.path == "/tmp/data")
    }

    @Test func ownMemoryBecomesARequest() {
        var form = AddAccountForm(); form.name = "Work"
        #expect(form.request.brain == nil && !form.request.ownBrain)
        form.memory = .own
        #expect(form.request.ownBrain && form.request.brain == nil)
        form.memory = .existing("client")
        #expect(form.request.brain == "client" && !form.request.ownBrain)
        form.memory = .shared
        #expect(form.request.brain == nil && !form.request.ownBrain)
    }
}
