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

    @Test func importLineEscapesSpaces() {
        let b = ManagedBlock.render(identityName: "Perso", slug: "perso", brainPath: "/Users/r/Obsidian Vault")
        #expect(b.contains("@/Users/r/Obsidian\\ Vault/BRAIN.md"))
        #expect(b.contains("Your shared brain is at /Users/r/Obsidian Vault."))
    }
}
