import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct IdentitySlugTests {
    @Test func accentsSpacesAndEmoji() {
        #expect(IdentitySlug.make(from: "Café/Du:Coin ✨") == "cafe-du-coin")
        #expect(IdentitySlug.make(from: "  Perso  ") == "perso")
        #expect(IdentitySlug.make(from: "Émilie Été") == "emilie-ete")
    }
    @Test func emptyAndLong() {
        #expect(IdentitySlug.make(from: "✨✨") == "identity")
        #expect(IdentitySlug.make(from: String(repeating: "a", count: 50)).count == 32)
    }
    @Test func uniqueness() {
        #expect(IdentitySlug.make(from: "Perso", taken: ["perso"]) == "perso-2")
        #expect(IdentitySlug.make(from: "Perso", taken: ["perso", "perso-2"]) == "perso-3")
    }
    @Test func bundleDisplayNameIsFileSafe() {
        let id = Identity(slug: "x", name: "Client/By:Taïsa ✨")
        #expect(id.bundleDisplayName == "Client-By-Taïsa ✨")
        #expect(id.gitAuthorEmail == "x@brainmerge.local")
    }
}
