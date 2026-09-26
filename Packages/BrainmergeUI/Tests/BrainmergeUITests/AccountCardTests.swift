import AppKit
import Foundation
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@Suite struct AccountCardTests {
    func account(running: Bool, session: Bool, version: ClaudeVersionState = .notApplicable) -> Account {
        Account(identity: Identity(slug: "work", name: "Work"), isRunning: running, hasSession: session, claudeVersion: version)
    }

    @Test func statusLinesSayWhatToDo() {
        #expect(AccountsView.status(of: account(running: false, session: false), memory: 0) == "Not logged in yet")
        #expect(AccountsView.status(of: account(running: true, session: false), memory: 0) == "Open · log in from its window")
        #expect(AccountsView.status(of: account(running: true, session: true), memory: 0) == "Open")
        #expect(AccountsView.status(of: account(running: false, session: true), memory: 0) == "Closed")
        let outdated = ClaudeVersionState.outdated(installed: "2.8000.0", built: "2.7032.0")
        #expect(AccountsView.status(of: account(running: false, session: true, version: outdated), memory: 0) == "Closed · built for Claude 2.7032.0, 2.8000.0 installed")
        #expect(AccountsView.status(of: account(running: true, session: true, version: outdated), memory: 0) == "Open · runs Claude 2.7032.0, 2.8000.0 installed")
    }

    func account(_ name: String, primary: Bool = false, note: String? = nil, email: String? = nil) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, note: note, isPrimary: primary), isRunning: false,
                codeAccount: email.map { ClaudeCodeAccount(email: $0) })
    }

    @Test func theSecondLineShowsTheClaudeCodeEmailWhenThereIsNoNote() {
        #expect(AccountsView.subtitle(of: account("Ruben", primary: true, email: "ruben@example.com")) == "ruben@example.com")
        #expect(AccountsView.subtitle(of: account("Ruben", primary: true)) == "Primary")
        #expect(AccountsView.subtitle(of: account("Work")) == "Account")
        // A note the person wrote comes first; the email then shows on the name's tooltip.
        let noted = account("Work", note: "Day job", email: "alex@example.com")
        #expect(AccountsView.subtitle(of: noted) == "Day job")
        #expect(AccountsView.nameHelp(of: noted) == "Claude Code is logged in as alex@example.com")
        #expect(AccountsView.nameHelp(of: account("Work", note: "Day job")) == nil)
        #expect(AccountsView.nameHelp(of: account("Work", email: "alex@example.com")) == nil)
    }

    /// Two accounts on one Claude account: the status keeps saying open or closed with the memory used, and a small
    /// mark next to the name carries the whole sentence, the other account's name included (a card is too narrow for it).
    @Test func twoAccountsOnOneClaudeAccountAreMarkedWithoutHidingTheStatus() {
        #expect(AccountsView.duplicateHelp(sameAs: "Agency") == "Same Claude account as Agency")
        // Binary units like Activity Monitor, and a point whatever the Mac's language.
        #expect(AccountsView.status(of: account(running: true, session: true), memory: 1_300_000_000) == "Open · 1.2 GB")
        #expect(AccountsView.status(of: account(running: false, session: true), memory: 0) == "Closed")
    }

    /// The email on the second line is cut in the middle on a narrow card: its tooltip shows it whole.
    @Test func theSecondLineShowsItsWholeTextOnHover() {
        #expect(AccountsView.subtitleHelp(of: account("Ruben", primary: true, email: "ruben@example.com")) == "ruben@example.com")
        #expect(AccountsView.subtitleHelp(of: account("Work", note: "Day job", email: "alex@example.com")) == "Day job")
        #expect(AccountsView.subtitleHelp(of: account("Work")) == nil)
    }

    /// A Claude Code only account has no window: its status says so rather than "Closed", and its card offers no Open.
    @Test func aClaudeCodeOnlyAccountSaysSo() {
        var identity = Identity(slug: "cli", name: "Terminal"); identity.surfaces = Surfaces(desktop: false, cli: true)
        let terminal = Account(identity: identity, isRunning: false, hasSession: false)
        #expect(AccountsView.status(of: terminal, memory: 0) == "Claude Code only")
        #expect(AccountsView.cardButton(for: terminal, action: .none) == nil)
    }

    /// The card's button says what the sidebar says, and is off where the sidebar is (a second click would open twice,
    /// or open a half-built app). Only the card offers "Update" for an outdated copy.
    @Test func theCardsButtonMatchesTheSidebar() {
        let closed = account(running: false, session: true), running = account(running: true, session: true)
        #expect(AccountsView.cardButton(for: closed, action: .open) == .init(label: "Open", run: .open, isEnabled: true, isProminent: true))
        #expect(AccountsView.cardButton(for: running, action: .show) == .init(label: "Show", run: .open, isEnabled: true, isProminent: false))
        #expect(AccountsView.cardButton(for: closed, action: .opening) == .init(label: "Opening…", run: .open, isEnabled: false, isProminent: true))
        #expect(AccountsView.cardButton(for: closed, action: .updating) == .init(label: "Updating…", run: .open, isEnabled: false, isProminent: true))
        #expect(AccountsView.cardButton(for: closed, action: .rebuild) == .init(label: "Rebuild", run: .rebuild, isEnabled: true, isProminent: true))
        let outdated = account(running: false, session: true, version: .outdated(installed: "2.8000.0", built: "2.7032.0"))
        #expect(AccountsView.cardButton(for: outdated, action: .open) == .init(label: "Update", run: .update, isEnabled: true, isProminent: true))
        #expect(AccountsView.cardButton(for: outdated, action: .updating)?.label == "Updating…")
    }

    /// An account that still has to log in: "Log in" takes the card's one button, prominent, and its Open (or Show)
    /// moves to the card's menu, where "Log in…" also is. While it opens, or its app is worked on or missing, the button
    /// says so as for any account. An outdated copy is updated first.
    @Test func logInTakesTheButtonOfAnAccountThatMustLogIn() {
        let fresh = account(running: false, session: false), open = account(running: true, session: false)
        let logIn = AccountsView.CardButton(label: "Log in", run: .logIn, isEnabled: true, isProminent: true)
        #expect(AccountsView.cardButton(for: fresh, action: .open) == logIn)
        #expect(AccountsView.cardButton(for: open, action: .show) == logIn)
        #expect(AccountsView.menuAction(for: fresh, action: .open) == .open)
        #expect(AccountsView.menuAction(for: open, action: .show) == .show)
        #expect(AccountsView.cardButton(for: fresh, action: .opening)?.label == "Opening…")
        #expect(AccountsView.cardButton(for: fresh, action: .updating)?.label == "Updating…")
        #expect(AccountsView.cardButton(for: fresh, action: .rebuild)?.label == "Rebuild")
        for action in [SidebarAccountAction.opening, .updating, .rebuild] { #expect(AccountsView.menuAction(for: fresh, action: action) == nil) }
        let outdated = account(running: false, session: false, version: .outdated(installed: "2.8000.0", built: "2.7032.0"))
        #expect(AccountsView.cardButton(for: outdated, action: .open)?.label == "Update")
        #expect(AccountsView.menuAction(for: outdated, action: .open) == nil)
        // Logged in: its Open stays on the card, nothing more in the menu.
        let closed = account(running: false, session: true)
        #expect(AccountsView.cardButton(for: closed, action: .open)?.label == "Open")
        #expect(AccountsView.menuAction(for: closed, action: .open) == nil)
    }

    // MARK: At the default window size

    /// `view` drawn at `width` on the app's dark background (10 points around it), as a window draws it.
    @MainActor static func render<V: View>(_ view: V, width: CGFloat) throws -> NSBitmapImageRep {
        let root = view.frame(width: width).fixedSize(horizontal: false, vertical: true).padding(10)
            .background(Color.black).environment(\.colorScheme, .dark)
        let window = TimelineDrawingTests.window(for: root)
        defer { window.orderOut(nil) }
        window.appearance = NSAppearance(named: .darkAqua)
        let content = try #require(window.contentView)
        window.setContentSize(content.fittingSize)
        let settle = Date().addingTimeInterval(0.3)
        while Date() < settle { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        return rep
    }

    /// A pixel of cream text on the dark background: bright, with little color (the orbs, the purple and the glass are not).
    static func isInk(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        let low = min(c.redComponent, c.greenComponent, c.blueComponent), high = max(c.redComponent, c.greenComponent, c.blueComponent)
        return low > 0.35 && high - low < 0.2
    }

    /// The ink of `rep`, in pixels, between the points `from` and `to` across (all of it by default).
    static func ink(_ rep: NSBitmapImageRep, from: CGFloat = 0, to: CGFloat = .infinity) -> Int {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let x0 = max(0, Int(from * scale)), x1 = min(rep.pixelsWide, Int(min(to * scale, CGFloat(rep.pixelsWide))))
        var count = 0
        for y in 0..<rep.pixelsHigh { for x in x0..<x1 where isInk(rep, x, y) { count += 1 } }
        return count
    }

    /// The ink pixels of `a` and `b` that differ between the points `from` and `to` across, over the height they share.
    static func differingInk(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, from: CGFloat, to: CGFloat) -> Int {
        let scale = CGFloat(a.pixelsWide) / a.size.width
        var count = 0
        for y in 0..<min(a.pixelsHigh, b.pixelsHigh) {
            for x in Int(from * scale)..<Int(to * scale) where isInk(a, x, y) != isInk(b, x, y) { count += 1 }
        }
        return count
    }

    /// Client, which still has to log in, with a note; `failed`: its last save failed three hours ago.
    @MainActor func client(failed: Bool) throws -> (ManagerEnv, AppModel, Account) {
        let e = try ManagerEnv.make()
        _ = try e.manager.adoptPrimary(name: "Personal")
        var request = IdentityManager.AddRequest(name: "Client"); request.note = "Client"
        _ = try e.manager.add(request)
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: ProcessMonitor(psOutput: { "" }))
        let m = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        m.readMacMemory = { _ in nil }
        m.environment = [:]
        m.reload()
        let now = Date()
        m.now = { now }
        if failed {
            SaveStatusStore(paths: e.home.paths).write(SaveStatus(date: now.addingTimeInterval(-3 * 3600), outcome: .failed, reason: .locked), slug: "client")
            m.refreshMemory()
        }
        let client = try #require(m.accounts.first { $0.id == "client" })
        #expect(client.needsLogin && !client.isRunning && (m.saveFailureSentence(of: "client") != nil) == failed)
        return (e, m, client)
    }

    /// At the default window (960 points wide, also the narrowest it gets) the grid gives each card 330 points. A card
    /// that still has to log in keeps its status whole: its text column draws "Not logged in yet" as a wide card does,
    /// never "Not l…".
    @MainActor @Test func aCardOfTheDefaultWindowKeepsItsStatusWhole() throws {
        let (e, m, client) = try client(failed: false); defer { e.home.remove() }
        let narrow = try Self.render(AccountsView(model: m).card(client), width: 330)
        let wide = try Self.render(AccountsView(model: m).card(client), width: 1000)
        let status = NSHostingView(rootView: Text("Not logged in yet").font(Theme.Fonts.caption).fixedSize()).fittingSize.width
        // From the card's left edge to past the end of the status: the orb, then the name, the note and the status.
        let end = 10 + 14 + 40 + 12 + status + 4
        let text = Self.ink(wide, from: 10, to: end)
        let differing = Self.differingInk(narrow, wide, from: 10, to: end)
        #expect(text > 200 && differing * 50 < text, "the card's words at 330 points differ from a wide card's: \(differing) of \(text) ink pixels")
    }

    /// The line of a failed save says why in full, on lines of its own under the card's row, never cut to "Last / sav…":
    /// the card with it holds all the ink of that sentence.
    @MainActor @Test func aFailedSaveIsSaidInFullOnACardOfTheDefaultWindow() throws {
        let (e1, quiet, calm) = try client(failed: false); defer { e1.home.remove() }
        let (e2, m, client) = try client(failed: true); defer { e2.home.remove() }
        let failure = try #require(m.saveFailureSentence(of: "client"))
        let without = Self.ink(try Self.render(AccountsView(model: quiet).card(calm), width: 330))
        let with = Self.ink(try Self.render(AccountsView(model: m).card(client), width: 330))
        let sentence = Self.ink(try Self.render(Text(failure).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted).fixedSize(), width: 600))
        #expect(sentence > 300 && Double(with - without) >= 0.9 * Double(sentence),
                "the card draws \(with - without) ink pixels of the \(sentence) its failed save needs")
    }
}
