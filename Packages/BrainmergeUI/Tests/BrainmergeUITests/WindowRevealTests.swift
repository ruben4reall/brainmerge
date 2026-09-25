import Foundation
import Testing
@testable import BrainmergeUI

/// "Show" on a running account: Claude keeps running with its window closed, so bringing the process forward is not
/// enough. When the account's app is the only one of its kind running, it is opened again (as a Dock click does) and
/// Claude shows its window; when another account runs the same app, only the process is brought forward.
@Suite struct WindowRevealTests {
    let claude = URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true)
    let copy = URL(fileURLWithPath: "/Users/alex/Applications/Brainmerge/Work (Claude).app", isDirectory: true)

    @Test func theOnlyInstanceOfItsAppIsOpenedAgain() {
        let running: [(pid: Int32, bundle: URL?)] = [(800, claude), (900, copy), (1000, nil)]
        #expect(WindowReveal.of(pid: 800, bundle: claude, running: running) == .reopen(claude))
        #expect(WindowReveal.of(pid: 900, bundle: copy, running: running) == .reopen(copy))
    }

    @Test func anAppSharedWithAnotherAccountIsOnlyBroughtForward() {
        // The primary and a secondary opened through its launcher both run Claude's own app: a reopen could reach either.
        let shared = URL(fileURLWithPath: "/Applications/Claude.app/", isDirectory: true)
        let running: [(pid: Int32, bundle: URL?)] = [(800, claude), (900, shared)]
        #expect(WindowReveal.of(pid: 800, bundle: claude, running: running) == .activate)
        #expect(WindowReveal.of(pid: 900, bundle: shared, running: running) == .activate)
    }

    @Test func aProcessWithoutAnAppIsOnlyBroughtForward() {
        #expect(WindowReveal.of(pid: 800, bundle: nil, running: [(800, nil)]) == .activate)
    }

    @Test func onlyClaudeAndBrainmergesAppsAreShown() {
        #expect(WindowReveal.isClaude(bundleIdentifier: "com.anthropic.claudefordesktop"))
        #expect(WindowReveal.isClaude(bundleIdentifier: "ch.rubencatalao.brainmerge.launch.work"))
        #expect(!WindowReveal.isClaude(bundleIdentifier: "com.apple.finder"))
        #expect(!WindowReveal.isClaude(bundleIdentifier: "ch.rubencatalao.brainmerge"))
        #expect(!WindowReveal.isClaude(bundleIdentifier: nil))
    }
}
