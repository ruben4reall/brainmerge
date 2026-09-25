import Foundation
import Testing
@testable import BrainmergeCore

/// A vault's `.obsidian/graph.json` and `app.json`, read the way Obsidian reads them, and the numbers Obsidian derives
/// from them (forces from slider positions, node size, label fade). Expected values come from Obsidian 1.13.7's own code.
@Suite struct ObsidianGraphSettingsTests {
    /// The owner's graph.json shape: filters, eleven color groups (two here), display and forces, saved zoom.
    static let graphJSON = #"""
    {
      "collapse-filter": true,
      "search": "-path:\"01 Journal\" -path:\"99 Système\" -path:\"98 Mémoire Claude/Sessions\" -file:\"MEMORY\"",
      "showTags": false,
      "showAttachments": false,
      "hideUnresolved": true,
      "showOrphans": true,
      "collapse-color-groups": false,
      "colorGroups": [
        {"query": "path:\"98 Mémoire Claude\"", "color": {"a": 1, "rgb": 1419967}},
        {"query": "path:\"05 Ressources\" OR path:\"06 Personnes\"", "color": {"a": 0.5, "rgb": 11133771}}
      ],
      "collapse-display": true,
      "showArrow": false,
      "textFadeMultiplier": 0,
      "nodeSizeMultiplier": 1,
      "lineSizeMultiplier": 1,
      "collapse-forces": true,
      "centerStrength": 0.518713248970312,
      "repelStrength": 10,
      "linkStrength": 1,
      "linkDistance": 250,
      "scale": 0.550052878597119,
      "close": true
    }
    """#

    @Test func theOwnersGraphJSONIsReadWhole() {
        let s = ObsidianGraphSettings.parse(graph: Data(Self.graphJSON.utf8), app: Data(#"{"userIgnoreFilters": ["99 Système/Templates/"]}"#.utf8))
        #expect(s.search == #"-path:"01 Journal" -path:"99 Système" -path:"98 Mémoire Claude/Sessions" -file:"MEMORY""#)
        #expect(!s.showAttachments && s.hideUnresolved && s.showOrphans && !s.showArrow)
        #expect(s.colorGroups.map(\.query) == [#"path:"98 Mémoire Claude""#, #"path:"05 Ressources" OR path:"06 Personnes""#])
        #expect(s.colorGroups.map(\.color.alpha) == [1, 0.5])
        #expect(abs(s.scale - 0.550052878597119) < 1e-12)
        #expect(s.linkDistance == 250 && s.repelStrength == 10)
        #expect(s.ignoreFilters == ["99 Système/Templates/"])
    }

    /// Nothing saved, or a file Obsidian never wrote: Obsidian's own defaults (its g0, v0 and a$ objects).
    @Test func missingOrBrokenFilesGiveObsidiansDefaults() {
        for data in [nil, Data(), Data("not json".utf8), Data("[1, 2]".utf8)] as [Data?] {
            let s = ObsidianGraphSettings.parse(graph: data, app: data)
            #expect(s.search == "" && s.colorGroups.isEmpty && s.ignoreFilters.isEmpty)
            #expect(s.showOrphans && !s.showAttachments && !s.hideUnresolved && !s.showArrow)
            #expect(abs(s.centerStrength - 0.518713248970312) < 1e-12)
            #expect(s.repelStrength == 10 && s.linkStrength == 1 && s.linkDistance == 250)
            #expect(s.nodeSizeMultiplier == 1 && s.lineSizeMultiplier == 1 && s.textFadeMultiplier == 0 && s.scale == 1)
        }
    }

    /// One wrong value costs only that value, one broken group only that group; values beyond Obsidian's sliders are
    /// brought back inside them.
    @Test func eachValueFailsAlone() {
        let json = #"""
        {"search": 42, "showOrphans": false, "linkDistance": "far", "repelStrength": 900, "nodeSizeMultiplier": 0,
         "textFadeMultiplier": -7, "scale": 0,
         "colorGroups": [{"query": "path:a"}, {"query": "path:b", "color": {"a": 1, "rgb": 255}}, 7]}
        """#
        let s = ObsidianGraphSettings.parse(graph: Data(json.utf8), app: Data(#"{"userIgnoreFilters": "x"}"#.utf8))
        #expect(s.search == "" && !s.showOrphans && s.linkDistance == 250)
        #expect(s.repelStrength == 20 && s.nodeSizeMultiplier == 0.1 && s.textFadeMultiplier == -3)
        #expect(s.scale == 1.0 / 128)
        #expect(s.colorGroups.map(\.query) == ["path:b"])
        #expect(s.ignoreFilters.isEmpty)
    }

    /// Colors are stored as one integer; the group's color is its three bytes.
    @Test func colorsComeFromRGBIntegers() {
        let teal = ObsidianGraphSettings.GroupColor(rgb: 1419967, alpha: 1)
        #expect((teal.red, teal.green, teal.blue) == (0x15, 0xAA, 0xBF))
        #expect(teal.hex == "#15AABF")
        #expect(ObsidianGraphSettings.GroupColor(rgb: 16612884, alpha: 1).hex == "#FD7E14")
        #expect(ObsidianGraphSettings.GroupColor(rgb: 11133771, alpha: 1).hex == "#A9E34B")
        #expect(ObsidianGraphSettings.GroupColor(rgb: 0, alpha: 1).hex == "#000000")
    }

    /// The force panel's sliders are positions, not forces: center and link go through Obsidian's curve
    /// (0.01^(1-v) - 0.01) / 0.99, repel is cubed with a floor of 1, the link distance is sent as it is.
    @Test func forcesAreConvertedLikeObsidian() {
        var s = ObsidianGraphSettings()
        #expect(abs(s.centerForce - 0.1) < 1e-9)
        #expect(s.repelForce == 1000)
        #expect(s.linkForce == 1)
        #expect(s.linkDistance == 250)
        s.centerStrength = 1; s.linkStrength = 0; s.repelStrength = 0
        #expect(abs(s.centerForce - 1) < 1e-12)
        #expect(s.linkForce == 0)
        #expect(s.repelForce == 1)
        s.centerStrength = 0; s.repelStrength = 20; s.linkStrength = 0.5
        #expect(s.centerForce == 0)
        #expect(s.repelForce == 8000)
        #expect(abs(s.linkForce - 0.090909090909) < 1e-9)
    }

    /// A node's size grows with its links (in and out, so a mutual link counts twice) from a floor of 8 to a cap of 30.
    @Test func nodeSizeFollowsObsidiansFormula() {
        #expect(ObsidianGraphSettings.nodeSize(weight: 0, multiplier: 1) == 8)
        #expect(ObsidianGraphSettings.nodeSize(weight: 6, multiplier: 1) == 8)
        #expect(abs(ObsidianGraphSettings.nodeSize(weight: 38, multiplier: 1) - 3 * 39.0.squareRoot()) < 1e-9)
        #expect(ObsidianGraphSettings.nodeSize(weight: 500, multiplier: 1) == 30)
        #expect(ObsidianGraphSettings.nodeSize(weight: 0, multiplier: 2) == 16)
    }

    /// Labels fade in with the zoom: clamp(log2(scale) + 1 - textFadeMultiplier, 0, 1).
    @Test func labelsFadeInWithTheZoom() {
        #expect(ObsidianGraphSettings.labelAlpha(scale: 1, fade: 0) == 1)
        #expect(ObsidianGraphSettings.labelAlpha(scale: 4, fade: 0) == 1)
        #expect(ObsidianGraphSettings.labelAlpha(scale: 0.5, fade: 0) == 0)
        #expect(ObsidianGraphSettings.labelAlpha(scale: 0.25, fade: 0) == 0)
        #expect(abs(ObsidianGraphSettings.labelAlpha(scale: 0.550052878597119, fade: 0) - 0.1386) < 0.001)
        #expect(ObsidianGraphSettings.labelAlpha(scale: 0.5, fade: -1) == 1)
        #expect(ObsidianGraphSettings.labelAlpha(scale: 2, fade: 3) == 0)
    }

    /// Only the two files are read, in the vault's `.obsidian` folder; a scale-only change is not a change of the look.
    @Test func settingsAreReadFromTheVault() throws {
        let vault = FileManager.default.temporaryDirectory.appending(path: "brainmerge-tests-\(UUID().uuidString)/Vault", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
        try Data(Self.graphJSON.utf8).write(to: vault.appending(path: ".obsidian/graph.json"))
        let s = ObsidianGraphSettings.read(vault: vault)
        #expect(s.hideUnresolved && s.colorGroups.count == 2)
        var zoomed = s
        zoomed.scale = 2
        #expect(zoomed.sameLook(as: s))
        zoomed.linkDistance = 100
        #expect(!zoomed.sameLook(as: s))
        #expect(ObsidianGraphSettings.read(vault: vault.appending(path: "nowhere")) == ObsidianGraphSettings())
    }
}
