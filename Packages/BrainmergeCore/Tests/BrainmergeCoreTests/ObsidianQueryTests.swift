import Foundation
import Testing
@testable import BrainmergeCore

/// The part of Obsidian's search language the graph's filter and color groups use: `path:`, `file:`, `-`, `OR`,
/// quoted values, case-insensitive. Anything else is left out of the query, never a crash.
@Suite struct ObsidianQueryTests {
    static let ownersSearch = #"-path:"01 Journal" -path:"99 Système" -path:"98 Mémoire Claude/Sessions" -file:"MEMORY""#

    @Test func theOwnersSearchHidesJournalSystemSessionsAndIndexes() {
        let q = ObsidianQuery(Self.ownersSearch)
        #expect(!q.matches(path: "01 Journal/2026-09-24.md"))
        #expect(!q.matches(path: "99 Système/Templates/Daily.md"))
        #expect(!q.matches(path: "99 Système/Dashboard.base"))
        #expect(!q.matches(path: "98 Mémoire Claude/Sessions/2026-09-24 Launch.md"))
        #expect(!q.matches(path: "98 Mémoire Claude/MEMORY.md"))
        #expect(q.matches(path: "98 Mémoire Claude/feedback_tone.md"))
        #expect(q.matches(path: "02 Projets/Orchard/Orchard.md"))
        #expect(q.matches(path: "HOME.md"))
    }

    @Test func pathAndFileMatchWithoutCaseOrNormalizationTrouble() {
        #expect(ObsidianQuery(#"path:"02 projets/orchard""#).matches(path: "02 Projets/Orchard/Plan.md"))
        // The folder written with a combining accent on disk, the query with a precomposed one.
        #expect(ObsidianQuery(#"path:"98 Mémoire Claude""#).matches(path: "98 Me\u{301}moire Claude/a.md"))
        // file: looks at the file's name, extension included, never at its folders.
        #expect(ObsidianQuery(#"file:"memory""#).matches(path: "notes/MEMORY.md"))
        #expect(ObsidianQuery("file:.canvas").matches(path: "Boards/Plan.canvas"))
        #expect(!ObsidianQuery(#"file:"Boards""#).matches(path: "Boards/Plan.canvas"))
        // A path value may name a note with its extension, as the owner's groups do.
        #expect(ObsidianQuery(#"path:"03 Domaines/Orchard.md""#).matches(path: "03 Domaines/Orchard.md"))
        #expect(!ObsidianQuery(#"path:"03 Domaines/Orchard.md""#).matches(path: "03 Domaines/Kiln.md"))
    }

    @Test func orAndImplicitAndAndParentheses() {
        let group = ObsidianQuery(#"path:"02 Projets/Orchard" OR path:"03 Domaines/Orchard.md" OR path:"06 Personnes/Ada Lovelace.md""#)
        #expect(group.matches(path: "02 Projets/Orchard/Orchard · Tech.md"))
        #expect(group.matches(path: "06 Personnes/Ada Lovelace.md"))
        #expect(!group.matches(path: "06 Personnes/Grace Hopper.md"))
        // Juxtaposed terms all have to match; OR binds looser than that.
        let both = ObsidianQuery("path:Projets file:Plan OR path:Inbox")
        #expect(both.matches(path: "02 Projets/Orchard/Plan.md"))
        #expect(!both.matches(path: "02 Projets/Orchard/Tech.md"))
        #expect(both.matches(path: "00 Inbox/Idea.md"))
        let grouped = ObsidianQuery("path:Projets (file:Plan OR file:Tech)")
        #expect(grouped.matches(path: "02 Projets/Orchard/Tech.md"))
        #expect(!grouped.matches(path: "00 Inbox/Plan.md"))
        #expect(ObsidianQuery("-(path:Inbox OR path:Journal)").matches(path: "HOME.md"))
        #expect(!ObsidianQuery("-(path:Inbox OR path:Journal)").matches(path: "01 Journal/x.md"))
    }

    /// Terms Brainmerge cannot evaluate (a word searched in the text, tags, other operators, regular expressions) are
    /// left out: they never hide or color a note by mistake, and a broken query never stops the graph.
    @Test func unknownTermsAreLeftOutAndNothingCrashes() {
        #expect(ObsidianQuery("tag:#work").isEmpty)
        #expect(ObsidianQuery("meeting").isEmpty)
        #expect(ObsidianQuery("").isEmpty && ObsidianQuery("   ").isEmpty)
        #expect(ObsidianQuery("").matches(path: "any.md"))   // an empty filter keeps everything
        #expect(ObsidianQuery("-tag:#draft path:Inbox").matches(path: "00 Inbox/a.md"))
        #expect(!ObsidianQuery("-tag:#draft path:Inbox").matches(path: "HOME.md"))
        #expect(ObsidianQuery("path:Inbox OR content:hello").matches(path: "00 Inbox/a.md"))
        #expect(!ObsidianQuery("path:Inbox OR content:hello").matches(path: "HOME.md"))
        #expect(ObsidianQuery("/regex.*/").isEmpty)
        #expect(ObsidianQuery("[status:done]").isEmpty)
        for broken in [#"path:"unclosed"#, "((path:a", "path:a))", "OR OR", "-", "path:", "--path:a", #"file:"""#, "path:(a b)", "\u{0}"] {
            _ = ObsidianQuery(broken).matches(path: "a/b.md")
        }
        #expect(ObsidianQuery(#"path:"unclosed"#).matches(path: "x/unclosed.md"))
        #expect(ObsidianQuery("path:a))").matches(path: "a.md"))
    }
}
