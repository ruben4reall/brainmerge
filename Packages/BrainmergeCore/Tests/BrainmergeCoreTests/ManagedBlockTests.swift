import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct ManagedBlockTests {
    let block = ManagedBlock.render(identityName: "Client", slug: "client", brainPath: "/Users/r/Brain")

    @Test func renderContainsImportAndIdentity() {
        #expect(block.hasPrefix(ManagedBlock.start))
        #expect(block.hasSuffix(ManagedBlock.end))
        #expect(block.contains("@/Users/r/Brain/BRAIN.md"))
        #expect(block.contains("identity \"Client\" (slug client)"))
    }

    @Test func upsertIntoEmptyAndExistingText() {
        #expect(ManagedBlock.upsert(in: "", block: block) == block + "\n")
        let user = "# Mes règles\n\n- pas de tiret cadratin\n"
        #expect(ManagedBlock.upsert(in: user, block: block) == user + "\n" + block + "\n")
    }

    @Test func upsertReplacesStaleBlockAndKeepsSurroundingText() {
        let stale = ManagedBlock.render(identityName: "Old", slug: "old", brainPath: "/old")
        let content = "avant\n\n" + stale + "\n\naprès\n"
        let out = ManagedBlock.upsert(in: content, block: block)
        #expect(out == "avant\n\n" + block + "\n\naprès\n")
        #expect(!out.contains("/old"))
    }

    @Test func removeKeepsUserText() {
        let content = "avant\n\n" + block + "\n\naprès\n"
        #expect(ManagedBlock.remove(from: content) == "avant\n\naprès\n")
        #expect(ManagedBlock.remove(from: "avant\n\n" + block + "\n") == "avant\n")
        #expect(ManagedBlock.remove(from: "rien\n") == "rien\n")
        #expect(ManagedBlock.contains(content))
        #expect(!ManagedBlock.contains("rien"))
    }

    /// The person deleted the end line: the next upsert appends a whole block, and the one after must replace only
    /// that block, never the person's lines after the orphan start. Remove leaves them too. A stray end line before
    /// the block is the person's text as well.
    @Test func orphanMarkersNeverTakeThePersonsText() {
        let stale = ManagedBlock.render(identityName: "Old", slug: "old", brainPath: "/old")
        let broken = "# Mine\n" + ManagedBlock.start + "\nMy rule one.\nMy rule two.\n"
        let once = ManagedBlock.upsert(in: broken, block: stale)
        #expect(once == broken + "\n" + stale + "\n")
        let twice = ManagedBlock.upsert(in: once, block: block)
        #expect(twice == broken + "\n" + block + "\n")
        #expect(ManagedBlock.remove(from: twice) == broken)
        let strayEnd = "# Mine\n" + ManagedBlock.end + "\nMy rule.\n\n" + stale + "\n"
        #expect(ManagedBlock.upsert(in: strayEnd, block: block) == "# Mine\n" + ManagedBlock.end + "\nMy rule.\n\n" + block + "\n")
    }

    @Test func importLineEscapesSpaces() {
        let b = ManagedBlock.render(identityName: "Perso", slug: "perso", brainPath: "/Users/r/Obsidian Vault")
        #expect(b.contains("@/Users/r/Obsidian\\ Vault/BRAIN.md"))
        #expect(b.contains("Your shared brain is at /Users/r/Obsidian Vault."))
    }
}
