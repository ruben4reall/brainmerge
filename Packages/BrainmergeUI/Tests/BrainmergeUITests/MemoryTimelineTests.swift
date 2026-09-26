import AppKit
import Foundation
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The Memory screen's timeline, filmed in the app's dark appearance as a new save drops in at the top.
@MainActor @Suite struct MemoryTimelineTests {
    /// The timeline alone, drawn again as the model changes.
    struct Timeline: View {
        let model: AppModel
        var body: some View { MemoryView(model: model).timeline.frame(width: 640).padding(20) }
    }

    /// A save by `identity` of `files` in the memory, as its Stop hook commits it.
    func save(_ e: ManagerEnv, _ identity: Identity, _ files: [String]) throws {
        for file in files {
            let url = e.brain.root.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(file)\n\(UUID().uuidString)\n".utf8).write(to: url)
        }
        _ = try BrainGit(brain: e.brain).commit(paths: files, author: BrainGit.Author(name: identity.name, email: identity.gitAuthorEmail)) {
            MemorySentence.message(name: identity.name, files: $0)
        }
    }

    /// A line of the rows' text column: a row's words (cream at full strength) or its detail line (muted cream).
    struct Line: Equatable { enum Kind { case words, detail }; let kind: Kind; let top: Int; let bottom: Int }

    /// The lines of `column` in `shot`, from the top, each at least 3 points tall (a glyph's soft edge is no line).
    static func lines(_ shot: Film.Shot, in column: Film.PixelRect) -> [Line] {
        var lines: [Line] = []
        var current: Line?
        for y in column.rows(in: shot) {
            var peak: CGFloat = 0
            for x in column.columns(in: shot) { peak = max(peak, shot.luma(x, y)) }
            let kind: Line.Kind? = peak > 0.8 ? .words : (peak > 0.4 ? .detail : nil)
            if let open = current, kind == open.kind {
                current = Line(kind: open.kind, top: open.top, bottom: y)
            } else {
                if let open = current { lines.append(open) }
                current = kind.map { Line(kind: $0, top: y, bottom: y) }
            }
        }
        if let open = current { lines.append(open) }
        return lines.filter { CGFloat($0.bottom - $0.top + 1) >= 3 * shot.scale }
    }

    /// The gap between the words and the detail line of each of the last `count` rows, from the bottom; nil for a row
    /// that is not a line of words over a detail line (they are drawn over each other).
    static func gaps(_ lines: [Line], last count: Int) -> [Int?] {
        var gaps: [Int?] = []
        var i = lines.count - 1
        while gaps.count < count, i >= 1 {
            if lines[i].kind == .detail, lines[i - 1].kind == .words {
                gaps.append(lines[i].top - lines[i - 1].bottom)
                i -= 2
            } else {
                gaps.append(nil)
                i -= 1
            }
        }
        return gaps
    }

    /// The rows under a new save slide down to make room for it, each as one piece: a row's words and its detail line
    /// under them keep their gap in every frame. The words, in the primary color, were drawn apart from the rest of the
    /// row (vibrant, inside the glass: the capture does not see them) and ran ahead of their detail line, over it.
    @Test func eachRowSlidesDownWhole() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let personal = try e.manager.adoptPrimary(name: "Personal")
        let studio = try e.manager.add(IdentityManager.AddRequest(name: "Studio"))
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try save(e, client, ["memory/client-site/a.md", "memory/client-site/b.md"])
        try save(e, personal, ["memory/mobile-app/c.md"])
        try save(e, studio, ["memory/newsletter/d.md"])
        try save(e, client, ["memory/client-site/g.md"])
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.environment = [:]
        m.reload()
        m.refreshMemory()
        let rows = m.memoryEvents.count
        #expect(rows == 4)
        let film = Film(Timeline(model: m), size: CGSize(width: 680, height: 700), dark: true)
        defer { film.close() }
        film.run(for: 0.4)
        let before = film.shot()
        let scale = before.scale
        // The rows' text column: past the page's padding, the row's own and the orb; short of the date on the right.
        let column = Film.PixelRect(x: Int((20 + MemoryView.rowInset) * scale), y: 0, width: Int(160 * scale), height: before.height)
        let rest = Self.lines(before, in: column)
        #expect(rest.filter { $0.kind == .words }.count == rows, "each row's words are drawn with the row: \(rest)")
        let resting = Self.gaps(rest, last: rows)
        let gap = try #require(resting.first ?? nil, "\(rest)")
        #expect(resting.allSatisfy { $0.map { abs($0 - gap) <= 1 } == true }, "\(resting)")

        try save(e, studio, ["memory/newsletter/e.md"])
        m.refreshMemory()
        #expect(m.memoryEvents.count == rows + 1)
        // The rows that were under the top one: the new save fades in over the one it pushes down, by design.
        let shots = film.shots(for: 0.7)
        for (time, shot) in shots {
            let now = Self.gaps(Self.lines(shot, in: column), last: rows - 1)
            #expect(now.allSatisfy { $0.map { abs($0 - gap) <= Int(2 * scale) } == true },
                    "\(Int(time * 1000)) ms after the save: gaps \(now) for \(gap)")
        }
        #expect(Self.lines(try #require(shots.last).shot, in: column).filter { $0.kind == .words }.count == rows + 1)
    }
}
